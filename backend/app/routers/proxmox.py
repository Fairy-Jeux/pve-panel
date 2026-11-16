"""Proxmox VE node supervision & VM/LXC power control endpoints."""

from typing import Literal

from fastapi import APIRouter, HTTPException, Request

from app.services.pve_client import ProxmoxClient

router = APIRouter(prefix="/api/pve", tags=["proxmox"])


@router.get("/overview")
async def get_pve_overview(request: Request) -> dict:
    """Return real-time Proxmox node metrics, storages, and VM/LXC list."""
    client = ProxmoxClient(request.app.state.pve_http)
    return await client.get_overview()


@router.post("/{vm_type}/{vmid}/{action}")
async def control_vm_or_lxc(
    request: Request,
    vm_type: Literal["lxc", "qemu"],
    vmid: int,
    action: Literal["start", "stop", "reboot", "shutdown"],
) -> dict:
    """Execute power action (start/stop/reboot/shutdown) on a container or VM."""
    client = ProxmoxClient(request.app.state.pve_http)
    try:
        return await client.execute_action(vm_type, vmid, action)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
