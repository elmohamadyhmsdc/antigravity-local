"""Offline address-change, QR, LAN discovery and interface selection regressions."""
import json
import socket
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from fastapi.testclient import TestClient
from mobile_api.app import create_app
from mobile_api.discovery import lan_addresses
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
