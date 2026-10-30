"""Resource status and opt-in admission settings for the desktop dashboard."""

from dataclasses import asdict

import streamlit as st

from resource_monitor import ResourceLimits, get_resource_monitor, load_limits, save_limits


def human_bytes(value):
    if value is None:
        return "Unavailable"
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024 or unit == "TiB":
            return f"{value:.1f} {unit}"
        value /= 1024


@st.fragment(run_every=5)
def render_resource_summary():
    monitor = get_resource_monitor()
    snapshot = monitor.snapshot()
    st.markdown("##### PC resources")
    st.caption("App RAM: " + human_bytes(snapshot["app_ram_bytes"]))
    if snapshot["gpus"]:
        gpu = snapshot["gpus"][0]
        st.caption("GPU 0 VRAM: " + human_bytes(gpu["used_bytes"]) + " / " + human_bytes(gpu["total_bytes"]))
    else:
        st.caption("VRAM: Unavailable")
    if snapshot["disk"]:
        st.caption("Disk free: " + human_bytes(snapshot["disk"]["free_bytes"]))
    for message in snapshot["alerts"]:
        st.warning(message)
    st.caption("Updates every 5 seconds. Details and protection: Settings.")


@st.fragment(run_every=5)
def render_resource_details():
    monitor = get_resource_monitor()
    snapshot = monitor.snapshot()
    ram, disk = snapshot["ram"], snapshot["disk"]
    cols = st.columns(3)
    cols[0].metric("Application RAM (RSS)", human_bytes(snapshot["app_ram_bytes"]))
    cols[1].metric("System RAM available", human_bytes(ram["available_bytes"] if ram else None))
    cols[2].metric("Workspace disk free", human_bytes(disk["free_bytes"] if disk else None))
    if ram:
        st.progress(min(1.0, max(0.0, ram["used_percent"] / 100)), text=f"System RAM: {ram['used_percent']:.1f}% used")
    for gpu in snapshot["gpus"]:
        st.markdown(f"**GPU {gpu['index']}: {gpu['name']}**")
        st.progress(min(1.0, gpu["used_bytes"] / max(1, gpu["total_bytes"])),
                    text=f"Whole GPU VRAM: {human_bytes(gpu['used_bytes'])} / {human_bytes(gpu['total_bytes'])}")
        st.caption(f"Application compute VRAM: {human_bytes(gpu['app_used_bytes'])}")
        if gpu["utilization_percent"] is not None:
            st.caption(f"GPU load: {gpu['utilization_percent']:.0f}%")
        if gpu["temperature_c"] is not None:
            st.caption(f"GPU temperature: {gpu['temperature_c']:.0f} °C")
    size = human_bytes(snapshot["app_storage_bytes"])
    st.caption(f"App folder files: {size}" + (" (still counting / partial)" if not snapshot["storage_complete"] else ""))
    st.caption("Folder size uses logical file sizes, refreshed at most once a minute. Linked external folders are excluded.")
    st.caption("Application RAM sums dashboard, server, queue and child-process RSS. Shared pages may be counted more than once. "
               "Process VRAM can be unavailable with this driver; whole-GPU VRAM includes other applications.")
    for message in snapshot["warnings"]:
        st.info(message)
    for message in snapshot["alerts"]:
        st.warning(message)
    with monitor._lock:
        history, events = list(monitor.history), list(monitor.events)
    if len(history) > 1:
        import pandas as pd
        data = pd.DataFrame(history).set_index("at")
        data.index = pd.to_datetime(data.index)
        st.line_chart(data[["app_ram_bytes", "gpu_used_bytes"]].rename(
            columns={"app_ram_bytes": "App RAM (GiB)", "gpu_used_bytes": "GPU 0 VRAM (GiB)"}) / (1024 ** 3))
    with st.expander("Measured processes and recent alerts"):
        st.dataframe(snapshot["processes"], hide_index=True)
        if events:
            st.dataframe(events, hide_index=True)
        else:
            st.caption("No resource alerts recorded in this process.")
        st.caption("History is bounded to 120 samples and 60 alerts in memory. It resets when this process restarts.")
    st.caption("Last sample (UTC): " + snapshot["sampled_at"])


def render_resource_settings():
    st.subheader("PC resources & protection")
    render_resource_details()
    from mobile_devices_page import local_dashboard_session
    if not local_dashboard_session():
        st.info("Open Settings using localhost on this PC to change resource protection.")
        return
    monitor = get_resource_monitor()
    try:
        limits = load_limits(monitor.app_dir)
    except (OSError, ValueError, TypeError):
        st.error("Resource settings could not be read. Saving below replaces the invalid settings.")
        limits = ResourceLimits()
    with st.form("resource-protection"):
        enabled = st.checkbox("Enable protection before starting compute work", value=limits.enabled)
        values = {}
        labels = {
            "max_app_ram_mb": "Application RAM threshold (MiB; 0 disables)",
            "min_free_ram_mb": "Keep system RAM available (MiB; 0 disables)",
            "min_free_vram_mb": "Keep GPU 0 VRAM available (MiB; 0 disables)",
            "min_free_disk_mb": "Keep workspace disk available (MiB; 0 disables)",
        }
        for key, label in labels.items():
            values[key] = st.number_input(label, min_value=0, max_value=16 * 1024 * 1024,
                                          value=asdict(limits)[key], step=128, key="resource-" + key)
        st.caption("Admission thresholds apply to desktop queued jobs and mobile image/video/Studio compute. "
                   "Desktop jobs pause before starting; mobile Studio waits, and scans return a retryable error. "
                   "Quick desktop actions and uploads are monitored but do not use these admission checks. "
                   "These are not hard memory caps: running work can exceed them. No process is killed, "
                   "no file is deleted, and user-paused jobs are never resumed automatically. "
                   "An enabled threshold with an unavailable measurement blocks new work; set that threshold to 0 to disable it.")
        if st.form_submit_button("Save resource protection"):
            try:
                save_limits(ResourceLimits(enabled=enabled, **values), monitor.app_dir)
            except (OSError, ValueError, TypeError):
                st.error("Could not save resource protection.")
            else:
                st.success("Resource protection saved. It applies to the next admission check.")
