"""Mobile pairing and device controls inside the existing web dashboard."""

import io
import ipaddress
from datetime import datetime

import streamlit as st

from mobile_dashboard_controller import MobileDashboardController, ControlError


@st.cache_resource
def mobile_controller():
    return MobileDashboardController()


def local_dashboard_session():
    """Use the server's WebSocket peer, not the frontend-supplied context IP."""
    try:
        from streamlit.runtime import get_instance
        from streamlit.runtime.scriptrunner import get_script_run_ctx
        context = get_script_run_ctx()
        client = get_instance().get_client(context.session_id) if context else None
        connection = getattr(client,'client_context',None)
        peer = connection.remote_ip if connection is not None else client.request.remote_ip
        return ipaddress.ip_address(peer).is_loopback
    except (AttributeError,RuntimeError,ValueError):
        return False


@st.cache_data(max_entries=8,show_spinner=False)
def pairing_qr(payload):
    import qrcode
    output = io.BytesIO()
    qrcode.make(payload,box_size=8,border=4).save(output)
    return output.getvalue()


def format_seen(value):
    if not value: return 'No activity yet'
    try: return datetime.fromisoformat(value).astimezone().strftime('%d %b %Y, %H:%M:%S')
    except ValueError: return 'Unknown'


def render_mobile_devices(controller=None, *, local_access=None):
    st.header('📱 Mobile Devices')
    st.caption('Pair Your Gallery with this PC and manage each phone’s access.')
    if not (local_dashboard_session() if local_access is None else local_access):
        st.info('Open this dashboard on the PC at http://localhost:8501/?page=mobile to manage phones.')
        return
    controller = controller or mobile_controller()

    def action(callback, message):
        try:
            callback()
            st.session_state['mobile_notice'] = message
            st.rerun()
        except ControlError as error:
            st.error(str(error))

    @st.fragment(run_every=3)
    def controls():
        state = controller.status(st.session_state.get('mobile_pair_host'))
        status = state['state']
        if notice := st.session_state.pop('mobile_notice',None): st.success(notice)
        if status not in ('running','starting','stopping'):
            st.subheader('Mobile server is off' if status == 'stopped' else 'Mobile server needs attention')
            st.write('Start the server here, then scan its QR code from the phone app.')
            if state.get('message'): st.warning(state['message'])
            if status == 'failed':
                with st.expander('Server diagnostics'):
                    st.code(controller.log_tail() or 'No server log was recorded.',language=None)
            if st.button('Start mobile server',key='mobile_start',type='primary',disabled=status=='external'):
                action(controller.start,'Starting the mobile server…')
            if status == 'external':
                st.link_button('Open existing pairing page',f'http://127.0.0.1:{controller.pair_port}/pair')
            with st.expander('Connection help'):
                st.write('Put the phone and PC on the same Wi-Fi or hotspot. Local pairing does not need Internet access.')
                st.write('If Windows asks, allow the existing Python app on Private networks. No firewall rules are changed here.')
            return

        top, stop = st.columns([4,1])
        with top:
            if status == 'running': st.success(f"Server online · {state['name']}")
            elif status == 'stopping': st.info('Stopping the mobile server…')
            else: st.info('Starting the mobile server…')
        with stop:
            if st.button('Stop server',key='mobile_stop',disabled=status!='running'):
                action(controller.stop,'Stopping the mobile server…')
        if status != 'running': return

        st.subheader('Connect a phone')
        addresses = state['addresses']
        old = st.session_state.get('mobile_pair_host',state['host'])
        if old not in addresses: st.session_state['mobile_pair_host'] = state['host']
        host = st.selectbox('PC address for the phone',addresses,
            index=addresses.index(old) if old in addresses else 0,key='mobile_pair_host',
            format_func=lambda ip:ip+(' · '+state.get('network',{}).get('labels',{}).get(ip,'')
                                     if state.get('network',{}).get('labels',{}).get(ip) else ''))
        if host != state['host']:
            state = controller.status(host)
            if state['state'] != 'running': return
        if host == '127.0.0.1':
            st.info('127.0.0.1 is for USB forwarding. For Wi-Fi or a hotspot, select the PC’s network address.')
        elif host == '10.0.2.2':
            st.info('10.0.2.2 is for an Android emulator. A physical phone needs the PC’s network address.')

        qr, instructions = st.columns([1,2])
        pairing = state['pairing']
        with qr:
            if pairing:
                st.image(pairing_qr(pairing['payload']),width=260)
            else:
                st.info('No active QR code. Generate a new code to pair another phone.')
        with instructions:
            st.write('1. Open Your Gallery on your phone.')
            st.write('2. Choose Scan QR and point the camera at this code.')
            st.write('3. The phone connects to this PC for GPU processing.')
            if pairing:
                st.code(pairing['code'],language=None)
                st.caption(f"Single use · expires in {pairing['remaining_seconds']} seconds")
            st.write(f"Manual address: {host} · port {state['api_port']}")
            if st.button('Generate new QR / code',key='mobile_new_code'):
                action(lambda:controller.new_code(host),'A new pairing code is ready.')
            if pairing and st.button('Cancel this code',key='mobile_cancel_code'):
                action(controller.cancel_code,'The pairing code has been invalidated.')
        with st.expander('Certificate fingerprint for manual pairing'):
            st.code(state['fingerprint'],language=None)
            st.caption('Compare this fingerprint with the one shown by the phone.')

        with st.expander('Connection help · hotspot / router / USB'):
            st.write('Phone hotspot: connect the PC to the phone, then select this PC’s Wi-Fi address above. The phone’s gateway address is not the PC address.')
            st.write('PC hotspot: connect the phone to the PC, then select the hotspot adapter address above. It can differ from the router/Ethernet address.')
            st.write('Addresses and the QR update automatically when adapters change. On the phone open Connection help → Find my PC, or verify the current address manually; pairing is preserved.')
            network = state.get('network',{})
            if network:
                st.caption(f"Listening on {network['bind']} · HTTPS TCP {state['api_port']} · discovery UDP {network['discovery_port']}")
                if not network['discovery_ready']: st.info('Local discovery is unavailable; QR and direct address connection remain available.')
            st.write('Windows Firewall must allow the existing Python server on the current network profile. Guest/client isolation and some VPNs can block local devices. USB forwarding is an alternative when LAN traffic is blocked.')
            st.code(f"adb reverse tcp:{state['api_port']} tcp:{state['api_port']}",language=None)
            st.caption('For USB forwarding, choose 127.0.0.1 above. USB debugging must be authorized on the phone.')
            from pathlib import Path
            script = Path(__file__).with_name('allow_mobile_lan.ps1')
            if script.is_file():
                st.download_button('Download scoped Windows firewall setup',script.read_text(encoding='utf-8'),
                    file_name='allow_mobile_lan.ps1',mime='text/plain')
                st.caption('Optional: run as administrator on this PC. The reviewed script allows only this Python executable and the local TCP/UDP ports from LocalSubnet on Private/Public networks; it does not disable the firewall.')
                st.code(f"& '{script}' -PythonPath '{script.parent/'venv'/'Scripts'/'python.exe'}' -ApiPort {state['api_port']} -DiscoveryPort {network.get('discovery_port',8445)}",language='powershell')

        st.divider()
        devices = state['devices']
        st.subheader(f'Paired phones ({len(devices)})')
        st.caption('“Active recently” means the phone contacted this PC within the last two minutes. This list updates every 3 seconds.')
        if not devices: st.info('No phones paired yet. Scan the QR above to add your first phone.')
        for device in devices:
            with st.container(border=True):
                details, buttons = st.columns([3,1])
                with details:
                    st.text(device['name'])
                    st.caption('🟢 Active recently' if device['active_recently'] else 'Paired · inactive')
                    st.caption('Last seen: '+format_seen(device['last_seen']))
                    st.caption(f"Paired: {format_seen(device['created_at'])} · Active jobs: {device['active_jobs']}")
                with buttons:
                    with st.popover('Rename'):
                        with st.form('mobile_rename_'+device['id']):
                            name = st.text_input('Phone name',value=device['name'],max_chars=64)
                            if st.form_submit_button('Save name'):
                                action(lambda:controller.rename(device['id'],name),'Phone renamed.')
                    with st.popover('Disconnect'):
                        st.write('Revoke this phone’s access and pause its PC jobs. It will need a new QR to reconnect.')
                        if st.button('Confirm disconnect',key='mobile_revoke_'+device['id']):
                            action(lambda:controller.revoke(device['id']),'Phone disconnected and its PC jobs paused.')
        if devices:
            with st.expander('Disconnect all phones'):
                st.write('Revoke every phone’s access, pause their jobs and invalidate the current pairing code.')
                if st.checkbox('Disconnect every paired phone',key='mobile_revoke_all_confirm'):
                    if st.button('Confirm disconnect all',key='mobile_revoke_all'):
                        action(controller.revoke_all,'All phones disconnected.')

    controls()
