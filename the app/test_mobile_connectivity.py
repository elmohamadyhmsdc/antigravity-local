"""Offline address-change, QR, LAN discovery and interface selection regressions."""
import json
import logging
import socket
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from mobile_api.app import create_app
from mobile_api.discovery import Discovery, lan_addresses
from mobile_api.lan_discovery import LanResponder, NetworkMonitor, private_v4, SERVICE
from mobile_api.pair_ui import create_pair_app
from mobile_api.pairing import parse_payload
from mobile_api.testing import make_test_context


class ConnectivityTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='ag_connectivity_')
        self.addCleanup(self.tmp.cleanup)
        self.ctx=make_test_context(Path(self.tmp.name))

    def test_address_change_refreshes_qr_and_mdns_without_changing_identity(self):
        calls=[]
        discovery=SimpleNamespace(stop=lambda:calls.append('stop'),start=lambda **kw:calls.append(kw['addresses']))
        addresses=['192.168.1.30']
        monitor=NetworkMonitor(self.ctx,discovery,addresses=lambda:list(addresses))
        self.ctx.pairing.issue()
        device=self.ctx.auth.add_device('Preserved phone')
        monitor.refresh()
        api=TestClient(create_app(self.ctx))
        with api,TestClient(create_pair_app(self.ctx)) as admin:
            headers={'X-Antigravity-Admin':self.ctx.admin_token}
            first=admin.get('/admin/status',headers=headers).json()
            addresses[:]=['10.183.49.149','192.168.137.1']
            monitor.refresh()
            result=admin.get('/admin/status?host=192.168.1.30',headers=headers).json()
            self.assertEqual(result['host'],'10.183.49.149')
            self.assertEqual(parse_payload(result['pairing']['payload'])['h'],'10.183.49.149')
            self.assertEqual(first['fingerprint'],result['fingerprint'])
            self.assertEqual(first['server_id'],result['server_id'])
            self.assertIsNotNone(self.ctx.auth.authenticate(device['token']))
            self.assertEqual(calls,['stop',['192.168.1.30'],'stop',['10.183.49.149','192.168.137.1']])
            self.assertEqual(admin.post('/admin/pairing',headers=headers,json={'host':'evil.example'}).status_code,400)

    def test_loopback_binding_does_not_offer_an_unreachable_lan_qr(self):
        self.ctx.bind_address='127.0.0.1'
        with TestClient(create_app(self.ctx)), TestClient(create_pair_app(self.ctx)) as admin:
            data=admin.get('/admin/status',headers={'X-Antigravity-Admin':self.ctx.admin_token}).json()
            self.assertEqual(data['addresses'],['127.0.0.1','10.0.2.2'])
            self.assertEqual(data['host'],'127.0.0.1')

    def test_address_reordering_does_not_restart_mdns(self):
        calls = []
        discovery = SimpleNamespace(stop=lambda: calls.append('stop'),
                                    start=lambda **kw: calls.append(kw['addresses']))
        addresses = ['192.168.137.34', '10.212.134.202']
        monitor = NetworkMonitor(self.ctx, discovery, addresses=lambda: list(addresses))
        monitor.refresh()
        addresses.reverse()
        monitor.refresh()
        self.assertEqual(len(calls), 2)
        self.assertEqual(self.ctx.host_addresses, addresses)
        addresses.remove('10.212.134.202')
        monitor.refresh()
        self.assertEqual(calls[-2:], ['stop', ['192.168.137.34']])

    def test_mdns_closes_sockets_even_if_unregister_fails(self):
        from unittest.mock import Mock
        discovery = Discovery()
        connection = Mock()
        connection.unregister_service.side_effect = OSError('adapter disconnected')
        discovery._zc, discovery._info = connection, object()
        discovery.stop()
        connection.close.assert_called_once()
        self.assertIsNone(discovery._zc)
        self.assertIsNone(discovery._info)

    def test_async_socket_failure_restarts_unchanged_interfaces_with_cooldown(self):
        discovery = Discovery(log=lambda *_: None)
        self.addCleanup(discovery.stop)
        connections = [Mock(), Mock(), Mock()]
        monitor = NetworkMonitor(self.ctx, discovery, addresses=lambda: ['10.23.1.246'])
        logger = logging.getLogger('zeroconf')
        error = OSError(59, 'An unexpected network error occurred')
        with patch('zeroconf.Zeroconf', side_effect=connections) as factory, patch(
                'mobile_api.lan_discovery.time.monotonic', return_value=0) as now:
            original_handlers = list(logger.handlers)
            monitor.refresh()
            self.assertEqual(factory.call_args.kwargs['interfaces'], ['10.23.1.246'])
            now.return_value = 3
            with self.assertLogs(level='WARNING'):
                logger.warning("Error with socket 2420 (('10.23.1.246', 5353))): %s",
                               error, exc_info=error)
            self.assertTrue(discovery.restart_requested)
            connections[0].close.assert_not_called()  # Never close on the log/event-loop thread.
            monitor.refresh()
            self.assertEqual(factory.call_count, 1)
            now.return_value = 30
            monitor.refresh()
            self.assertEqual(factory.call_count, 2)
            connections[0].close.assert_called_once()
            self.assertFalse(discovery.restart_requested)
            now.return_value = 33
            with self.assertLogs(level='WARNING'):
                logger.warning("Error with socket 2421 (('10.23.1.246', 5353))): %s",
                               error, exc_info=error)
            monitor.refresh()
            self.assertEqual(factory.call_count, 2)
            now.return_value = 60
            monitor.refresh()
            self.assertEqual(factory.call_count, 3)
            discovery.stop()
        self.assertEqual(logger.handlers, original_handlers)

    def test_unrelated_zeroconf_warnings_do_not_restart_discovery(self):
        discovery = Discovery(log=lambda *_: None)
        self.addCleanup(discovery.stop)
        with patch('zeroconf.Zeroconf'):
            self.assertTrue(discovery.start(name='PC', server_id='test', api_version='1',
                                            port=8443, addresses=['10.23.1.246']))
            with self.assertLogs(level='WARNING'):
                logger = logging.getLogger('zeroconf')
                logger.warning("Error with socket 9 (('192.168.1.2', 5353))): %s",
                               OSError(59, 'another interface'), exc_info=OSError(59, 'another interface'))
                logger.warning('Invalid packet', exc_info=ValueError('bad packet'))
            self.assertFalse(discovery.restart_requested)

    def test_failed_mdns_start_retries_without_an_address_change(self):
        discovery = Mock(restart_requested=False)
        discovery.start.side_effect = [False, True]
        monitor = NetworkMonitor(self.ctx, discovery, addresses=lambda: ['10.23.1.246'])
        with patch('mobile_api.lan_discovery.time.monotonic', return_value=0) as now:
            monitor.refresh()
            now.return_value = 3
            monitor.refresh()
            self.assertEqual(discovery.start.call_count, 1)
            now.return_value = 30
            monitor.refresh()
            self.assertEqual(discovery.start.call_count, 2)
            now.return_value = 60
            monitor.refresh()
            self.assertEqual(discovery.start.call_count, 2)

    def test_failed_registration_removes_error_handler_and_closes_socket(self):
        logger = logging.getLogger('zeroconf')
        discovery = Discovery(log=lambda *_: None)
        connection = Mock()
        connection.register_service.side_effect = OSError(59, 'adapter disconnected')
        with patch('zeroconf.Zeroconf', return_value=connection):
            original_handlers = list(logger.handlers)
            self.assertFalse(discovery.start(name='PC', server_id='test', api_version='1',
                                             port=8443, addresses=['10.23.1.246']))
        connection.close.assert_called_once()
        self.assertEqual(logger.handlers, original_handlers)

    def test_explicit_empty_mdns_interfaces_do_not_autodetect(self):
        with patch('mobile_api.discovery.lan_addresses') as detect:
            self.assertFalse(Discovery(log=lambda *_: None).start(
                name='PC', server_id='test', api_version='1', port=8443, addresses=[]))
            detect.assert_not_called()

    def test_windows_hotspot_adapter_is_found_even_when_not_in_dns(self):
        import psutil
        with patch('socket.getaddrinfo',return_value=[(socket.AF_INET,0,0,'',('10.99.1.3',0))]),patch.object(psutil,'net_if_stats',return_value={
            'hotspot':SimpleNamespace(isup=True),'unplugged':SimpleNamespace(isup=False)}),patch.object(
            psutil,'net_if_addrs',return_value={'hotspot':[SimpleNamespace(family=socket.AF_INET,address='192.168.137.1')],
                                              'unplugged':[SimpleNamespace(family=socket.AF_INET,address='10.1.1.3')]}):
            found=lan_addresses()
            self.assertIn('192.168.137.1',found)
            self.assertNotIn('10.1.1.3',found)
            self.assertNotIn('10.99.1.3',found,'Cached hostname DNS must not keep an unassigned old address in the QR choices.')

    def test_udp_round_trip_is_correlated_and_never_contains_secrets_or_pins(self):
        responder=LanResponder(self.ctx,bind='127.0.0.1',port=0)
        self.assertTrue(responder.start());self.addCleanup(responder.stop)
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as client:
            client.settimeout(1)
            request={'service':SERVICE,'version':1,'nonce':'ab'*16}
            client.sendto(json.dumps(request).encode(),('127.0.0.1',responder.port))
            response=json.loads(client.recvfrom(2048)[0])
            self.assertEqual(response['nonce'],request['nonce'])
            self.assertEqual(response['server_id'],self.ctx.auth.server_id)
            self.assertEqual(response['port'],self.ctx.api_port)
            self.assertNotIn('fingerprint',response)
            self.assertNotIn('token',response)
            self.assertNotIn(self.ctx.admin_token,json.dumps(response))
            client.settimeout(.08)
            for raw in (b'not json',b'[]',b'{}',b'x'*1025,json.dumps({**request,'nonce':'bad'}).encode()):
                client.sendto(raw,('127.0.0.1',responder.port))
                with self.assertRaises(socket.timeout):client.recvfrom(2048)

    def test_no_public_or_multicast_discovery_peers(self):
        for address in ('8.8.8.8','224.0.0.1','0.0.0.0','255.255.255.255','::1'):
            self.assertFalse(private_v4(address))
        for address in ('10.183.49.227','192.168.137.2','172.20.10.1','127.0.0.1'):
            self.assertTrue(private_v4(address))


if __name__=='__main__':unittest.main(verbosity=2)
