#!/usr/bin/env python3
"""Agente macOS per eseguire blocchi Photoshop e Illustrator del gestionale."""

import argparse
import json
import mimetypes
import os
import platform
import plistlib
import re
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


class AdobeAgent:
    KEYCHAIN_SERVICE = "it.magenta.adobe-agent"

    def __init__(self, config_path=None):
        default_config_path = (
            Path.home() / "Library" / "Application Support" / "Magenta Adobe Agent" / "config.json"
        )
        self.config_path = Path(
            config_path or os.environ.get("AUTOMATION_AGENT_CONFIG", default_config_path)
        ).expanduser()
        self.config = self.load_config()
        shared_root = (
            Path("/Users/Shared/MagentaAdobe")
            if platform.system() == "Darwin"
            else Path.home() / "MagentaAdobe"
        )
        self.base_url = self.setting(
            "AUTOMATION_BASE_URL", "base_url", "http://localhost:5010"
        ).rstrip("/")
        configured_agent_key = self.setting("AUTOMATION_AGENT_ID", "agent_key", "")
        self.agent_key_was_configured = bool(configured_agent_key)
        self.agent_key = configured_agent_key or f"adobe-{socket.gethostname().lower()}"
        self.agent_name = self.setting(
            "AUTOMATION_AGENT_NAME", "agent_name", socket.gethostname()
        )
        self.photoshop_app = self.setting(
            "ADOBE_PHOTOSHOP_APP", "photoshop_app", "Adobe Photoshop 2024"
        )
        self.illustrator_app = self.setting(
            "ADOBE_ILLUSTRATOR_APP", "illustrator_app", "Adobe Illustrator"
        )
        self.template_root = Path(
            self.setting(
                "AUTOMATION_TEMPLATE_ROOT",
                "template_root",
                str(shared_root / "illustrator" / "templates"),
            )
        ).expanduser()
        legacy_resource_root = (
            self.template_root.parent
            if "AUTOMATION_TEMPLATE_ROOT" in os.environ
            else None
        )
        self.script_root = Path(
            self.setting(
                "AUTOMATION_SCRIPT_ROOT",
                "script_root",
                str(
                    legacy_resource_root / "scripts"
                    if legacy_resource_root
                    else shared_root / "illustrator" / "scripts"
                ),
            )
        ).expanduser()
        self.action_inventory_path = Path(
            self.setting(
                "AUTOMATION_ACTION_INVENTORY",
                "action_inventory_path",
                str(
                    legacy_resource_root / "photoshop-actions.json"
                    if legacy_resource_root
                    else shared_root / "photoshop" / "actions.json"
                ),
            )
        ).expanduser()
        configured_hotfolder_roots = self.config.get(
            "hotfolder_roots", ["/Volumes/Public/hotfolder"]
        )
        self.hotfolder_roots = [
            Path(value).expanduser()
            for value in configured_hotfolder_roots
            if str(value).strip()
        ]
        self.token = os.environ.get("AUTOMATION_AGENT_TOKEN", "") or self.load_saved_token()
        self.last_error = None

    def setting(self, environment_name, config_name, default):
        return os.environ.get(environment_name, self.config.get(config_name, default))

    def load_config(self):
        if not self.config_path.is_file():
            return {}
        try:
            value = json.loads(self.config_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError(f"Configurazione agente non leggibile: {error}") from error
        if not isinstance(value, dict):
            raise RuntimeError("La configurazione agente deve essere un oggetto JSON")
        return value

    def load_saved_token(self):
        if platform.system() == "Darwin" and self.agent_key_was_configured:
            result = subprocess.run(
                [
                    "security",
                    "find-generic-password",
                    "-s",
                    self.KEYCHAIN_SERVICE,
                    "-a",
                    self.agent_key,
                    "-w",
                ],
                text=True,
                capture_output=True,
            )
            if result.returncode == 0:
                return result.stdout.strip()
        # Fallback per sviluppo e sistemi senza Portachiavi macOS.
        return str(self.config.get("token") or "")

    def save_token(self, token):
        if platform.system() != "Darwin":
            self.config["token"] = token
            return
        result = subprocess.run(
            [
                "security",
                "add-generic-password",
                "-U",
                "-s",
                self.KEYCHAIN_SERVICE,
                "-a",
                self.agent_key,
                "-w",
                token,
            ],
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise RuntimeError(
                result.stderr.strip() or "Impossibile salvare la credenziale nel Portachiavi macOS"
            )
        self.config.pop("token", None)

    def save_config(self):
        self.config.update(
            {
                "base_url": self.base_url,
                "agent_key": self.agent_key,
                "agent_name": self.agent_name,
                "photoshop_app": self.photoshop_app,
                "illustrator_app": self.illustrator_app,
                "template_root": str(self.template_root),
                "script_root": str(self.script_root),
                "action_inventory_path": str(self.action_inventory_path),
                "hotfolder_roots": [str(path) for path in self.hotfolder_roots],
            }
        )
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        temporary_path = self.config_path.with_suffix(".tmp")
        temporary_path.write_text(
            json.dumps(self.config, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        os.chmod(temporary_path, 0o600)
        temporary_path.replace(self.config_path)

    def prepare_directories(self):
        for directory in (
            self.template_root,
            self.script_root,
            self.action_inventory_path.parent,
        ):
            directory.mkdir(parents=True, exist_ok=True)

    def photoshop_actions(self):
        if self.action_inventory_path.is_file():
            try:
                actions = json.loads(self.action_inventory_path.read_text(encoding="utf-8"))
                if isinstance(actions, list):
                    return actions
            except (OSError, json.JSONDecodeError):
                pass

        # Compatibilità con l’inventario TSV prodotto dall’agente precedente.
        legacy_inventory = Path.home() / "AutomationAdobe" / "photoshop-actions.txt"
        if not legacy_inventory.is_file():
            return []
        try:
            actions = []
            for line in legacy_inventory.read_text(encoding="utf-8-sig").splitlines():
                action_set, separator, action_name = line.partition("\t")
                if separator and action_set.strip() and action_name.strip():
                    actions.append({"set": action_set.strip(), "name": action_name.strip()})
            return actions
        except OSError:
            return []

    @staticmethod
    def application_installed(app_name):
        applications_root = Path("/Applications")
        direct = applications_root / f"{app_name}.app"
        nested = applications_root.glob(f"*/{app_name}.app")
        return direct.is_dir() or any(candidate.is_dir() for candidate in nested)

    def request(self, path, *, payload=None, data=None, headers=None, timeout=60):
        request_headers = {"Accept": "application/json"}
        if self.token:
            request_headers["Authorization"] = f"Bearer {self.token}"
        request_headers.update(headers or {})
        body = data
        if payload is not None:
            body = json.dumps(payload).encode("utf-8")
            request_headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=body, headers=request_headers, method="POST" if body is not None else "GET"
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                content = response.read()
                return json.loads(content.decode("utf-8")) if content else {}
        except urllib.error.HTTPError as error:
            content = error.read().decode("utf-8", errors="replace")
            try:
                message = json.loads(content).get("error")
            except json.JSONDecodeError:
                message = content.strip()
            raise RuntimeError(message or f"Errore HTTP {error.code}") from error

    def agent_payload(self):
        def relative_resources(root, suffix):
            """Return stable relative paths, preserving subfolders for the UI."""
            if not root.is_dir():
                return []
            values = []
            for path in root.rglob(f"*{suffix}"):
                if path.is_file():
                    values.append(path.relative_to(root).as_posix())
            return sorted(values, key=str.casefold)

        return {
            "name": self.agent_name,
            "hostname": socket.gethostname(),
            "platform": f"{platform.system()} {platform.mac_ver()[0]}",
            "metadata": {
                "photoshop_app": self.photoshop_app,
                "illustrator_app": self.illustrator_app,
                "photoshop_installed": self.application_installed(self.photoshop_app),
                "illustrator_installed": self.application_installed(self.illustrator_app),
                "template_root": str(self.template_root),
                "script_root": str(self.script_root),
                "illustrator_templates": relative_resources(self.template_root, ".ai"),
                "illustrator_scripts": relative_resources(self.script_root, ".jsx"),
                "photoshop_actions": self.photoshop_actions(),
                "hotfolder_roots": [
                    {
                        "path": str(path),
                        "available": path.is_dir(),
                        "writable": os.access(path, os.W_OK),
                    }
                    for path in self.hotfolder_roots
                ],
                "agent_version": 7,
            },
            "last_error": self.last_error,
        }

    def pair(self, code):
        self.prepare_directories()
        response = self.request(
            "/api/automation/agent/pair",
            payload={
                "code": code,
                "worker_id": self.agent_key if self.agent_key_was_configured else None,
                "capabilities": ["photoshop", "illustrator", "hot_folder"],
                "agent": self.agent_payload(),
            },
        )
        agent = response.get("agent") or {}
        self.agent_key = str(agent["key"])
        self.agent_name = str(agent.get("name") or self.agent_name)
        self.token = str(agent["token"])
        self.agent_key_was_configured = True
        self.save_token(self.token)
        self.save_config()
        return response

    def scan_photoshop_actions(self):
        self.prepare_directories()
        with tempfile.TemporaryDirectory(prefix="magenta-adobe-actions-") as directory:
            workdir = Path(directory)
            report_path = workdir / "photoshop-actions.tsv"
            jsx = f"""#target photoshop
app.displayDialogs = DialogModes.NO;
var output = new File({self.jsx_string(report_path)});
output.encoding = "UTF8";
output.open("w");
var setIndex = 1;
while (true) {{
  try {{
    var setReference = new ActionReference();
    setReference.putIndex(charIDToTypeID("ASet"), setIndex);
    var setDescriptor = executeActionGet(setReference);
    var setName = setDescriptor.getString(charIDToTypeID("Nm  "));
    var actionCount = setDescriptor.getInteger(charIDToTypeID("NmbC"));
    for (var actionIndex = 1; actionIndex <= actionCount; actionIndex++) {{
      var actionReference = new ActionReference();
      actionReference.putIndex(charIDToTypeID("Actn"), actionIndex);
      actionReference.putIndex(charIDToTypeID("ASet"), setIndex);
      var actionDescriptor = executeActionGet(actionReference);
      output.writeln(setName + "\\t" + actionDescriptor.getString(charIDToTypeID("Nm  ")));
    }}
    setIndex++;
  }} catch (error) {{ break; }}
}}
output.close();
"""
            self.execute_jsx(self.photoshop_app, jsx, workdir / "list-actions.jsx")
            if not report_path.is_file():
                raise RuntimeError("Photoshop non ha restituito l’elenco delle azioni")
            actions = []
            for line in report_path.read_text(encoding="utf-8-sig").splitlines():
                action_set, separator, action_name = line.partition("\t")
                if separator and action_set.strip() and action_name.strip():
                    actions.append({"set": action_set.strip(), "name": action_name.strip()})
            self.action_inventory_path.write_text(
                json.dumps(actions, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            return actions

    def install_launch_agent(self):
        if platform.system() != "Darwin":
            raise RuntimeError("L’avvio automatico è disponibile soltanto su macOS")

        support_root = (
            Path.home() / "Library" / "Application Support" / "Magenta Adobe Agent"
        )
        helper_root = support_root / "agent"
        logs_root = support_root / "logs"
        launch_agents_root = Path.home() / "Library" / "LaunchAgents"
        for directory in (helper_root, logs_root, launch_agents_root):
            directory.mkdir(parents=True, exist_ok=True)

        installed_helper = helper_root / "adobe_agent.py"
        current_helper = Path(__file__).resolve()
        if current_helper != installed_helper:
            shutil.copy2(current_helper, installed_helper)
        os.chmod(installed_helper, 0o755)

        label = self.KEYCHAIN_SERVICE
        plist_path = launch_agents_root / f"{label}.plist"
        plist = {
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/python3",
                str(installed_helper),
                "--poll-seconds",
                "2",
            ],
            "RunAtLoad": True,
            "KeepAlive": True,
            "StandardOutPath": str(logs_root / "agent.log"),
            "StandardErrorPath": str(logs_root / "agent-error.log"),
        }
        plist_path.write_bytes(plistlib.dumps(plist))

        domain = f"gui/{os.getuid()}"
        subprocess.run(
            ["/bin/launchctl", "bootout", domain, str(plist_path)],
            text=True,
            capture_output=True,
        )
        result = subprocess.run(
            ["/bin/launchctl", "bootstrap", domain, str(plist_path)],
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise RuntimeError(
                result.stderr.strip() or "Impossibile avviare Magenta Adobe Agent"
            )
        return plist_path

    def claim(self):
        response = self.request(
            "/api/automation/agent/claim",
            payload={
                "worker_id": self.agent_key,
                "capabilities": ["photoshop", "illustrator", "hot_folder"],
                "agent": self.agent_payload(),
            },
        )
        command = response.get("command")
        if command:
            self.process_command(command)
        return response.get("task")

    def process_command(self, command):
        if command.get("type") != "sync_resources":
            raise RuntimeError(f"Comando agente non supportato: {command.get('type')}")
        try:
            actions = self.scan_photoshop_actions()
            self.last_error = None
            self.request(
                "/api/automation/agent/sync_complete",
                payload={
                    "worker_id": self.agent_key,
                    "capabilities": ["photoshop", "illustrator", "hot_folder"],
                    "agent": self.agent_payload(),
                },
            )
            print(
                f"[AdobeAgent] Risorse sincronizzate: {len(actions)} azioni Photoshop",
                flush=True,
            )
        except Exception as error:
            self.last_error = f"{type(error).__name__}: {error}"
            self.request(
                "/api/automation/agent/sync_complete",
                payload={
                    "worker_id": self.agent_key,
                    "capabilities": ["photoshop", "illustrator", "hot_folder"],
                    "agent": self.agent_payload(),
                    "error": self.last_error,
                },
            )
            raise

    def run(self, once=False, poll_seconds=2):
        print(f"[AdobeAgent] {self.agent_key} collegato a {self.base_url}", flush=True)
        while True:
            try:
                task = self.claim()
                if task:
                    self.process(task)
                    if once:
                        return
                elif once:
                    print("[AdobeAgent] Nessun lavoro disponibile", flush=True)
                    return
                else:
                    time.sleep(poll_seconds)
            except KeyboardInterrupt:
                return
            except Exception as error:
                self.last_error = f"{type(error).__name__}: {error}"
                print(f"[AdobeAgent] {self.last_error}", flush=True)
                if once:
                    raise
                time.sleep(poll_seconds)

    def process(self, task):
        try:
            with tempfile.TemporaryDirectory(prefix=f"automation-adobe-{task['step_id']}-") as directory:
                workdir = Path(directory)
                suffix = Path(task.get("input_filename") or "").suffix or ".bin"
                input_path = workdir / f"input{suffix}"
                input_path.write_bytes(self.download(task["input_url"]))
                output_path = workdir / f"{task['node_type']}.pdf"
                config = task.get("config") or {}
                execution_metadata = {}

                if task["node_type"] == "photoshop":
                    print(
                        f"[AdobeAgent] Photoshop step {task['step_id']}: "
                        f"set={config.get('action_set')!r}, azione={config.get('action_name')!r}, "
                        f"misura={config.get('width_mm') or 0}x{config.get('height_mm') or 0} mm, "
                        f"dpi={config.get('dpi') or 300}",
                        flush=True,
                    )
                    execution_metadata = self.execute_photoshop(
                        input_path, output_path, config, task.get("context") or {}, workdir
                    )
                elif task["node_type"] == "illustrator":
                    print(
                        f"[AdobeAgent] Illustrator step {task['step_id']}: "
                        f"script={config.get('script_name')!r}, "
                        f"maschera={config.get('template_path')!r}, preset={config.get('pdf_preset')!r}",
                        flush=True,
                    )
                    self.execute_illustrator(input_path, output_path, config, workdir)
                elif task["node_type"] == "hot_folder":
                    execution_metadata = self.execute_hot_folder(input_path, config)
                    output_path = input_path.with_name(
                        execution_metadata["delivered_filename"]
                    )
                else:
                    raise RuntimeError(f"Tipo agente non supportato: {task['node_type']}")

                if not output_path.is_file() or output_path.stat().st_size == 0:
                    raise RuntimeError("Adobe non ha prodotto il PDF atteso")
                self.complete(task, output_path, config, execution_metadata)
                self.last_error = None
                print(f"[AdobeAgent] Completato step {task['step_id']} ({task['node_type']})", flush=True)
        except Exception as error:
            self.fail(task, error)
            raise

    def download(self, path):
        request = urllib.request.Request(f"{self.base_url}{path}", headers={"Accept": "*/*"})
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.read()

    @staticmethod
    def context_value(context, path):
        value = context
        for key in str(path or "").split("."):
            value = value.get(key) if isinstance(value, dict) else None
        return value

    @staticmethod
    def jsx_string(value):
        return json.dumps(str(value))

    def execute_photoshop(self, input_path, output_path, config, context, workdir):
        action_set = str(config.get("action_set") or "").strip()
        action_name = str(config.get("action_name") or "").strip()
        target_dpi = float(config.get("dpi") or 300)
        width_mm = float(config.get("width_mm") or 0)
        height_mm = float(config.get("height_mm") or 0)
        if (width_mm > 0) != (height_mm > 0):
            raise RuntimeError("Larghezza e altezza Photoshop devono essere entrambe maggiori di zero")
        resize_applied = width_mm > 0 and height_mm > 0
        target_width_px = round(width_mm / 25.4 * target_dpi) if resize_applied else None
        target_height_px = round(height_mm / 25.4 * target_dpi) if resize_applied else None
        resize_jsx = (
            f'documentRef.resizeImage(UnitValue({target_width_px}, "px"), '
            f'UnitValue({target_height_px}, "px"), {target_dpi}, ResampleMethod.BICUBIC);'
            if resize_applied else
            f"documentRef.resizeImage(undefined, undefined, {target_dpi}, ResampleMethod.NONE);"
        )
        dpi_report_path = workdir / "photoshop-dpi.json"
        jsx = f"""#target photoshop
app.displayDialogs = DialogModes.NO;
var inputFile = new File({self.jsx_string(input_path)});
var outputFile = new File({self.jsx_string(output_path)});
var reportFile = new File({self.jsx_string(dpi_report_path)});
var documentRef = app.open(inputFile);
if ({self.jsx_string(action_set)} !== "" && {self.jsx_string(action_name)} !== "") {{
  app.doAction({self.jsx_string(action_name)}, {self.jsx_string(action_set)});
}}
documentRef = app.activeDocument;
var pixelsBeforeWidth = Math.round(documentRef.width.as("px"));
var pixelsBeforeHeight = Math.round(documentRef.height.as("px"));
{resize_jsx}
var pixelsAfterWidth = Math.round(documentRef.width.as("px"));
var pixelsAfterHeight = Math.round(documentRef.height.as("px"));
reportFile.open("w");
reportFile.write('{{"pixels_before":[' + pixelsBeforeWidth + ',' + pixelsBeforeHeight +
  '],"pixels_after":[' + pixelsAfterWidth + ',' + pixelsAfterHeight +
  '],"dpi":' + documentRef.resolution +
  ',"resize_applied":{str(resize_applied).lower()}' +
  ',"width_mm":{width_mm},"height_mm":{height_mm}' +
  '}}');
reportFile.close();
var saveOptions = new PDFSaveOptions();
saveOptions.embedColorProfile = true;
saveOptions.preserveEditing = false;
documentRef.saveAs(outputFile, saveOptions, true, Extension.LOWERCASE);
documentRef.close(SaveOptions.DONOTSAVECHANGES);
"""
        self.execute_jsx(self.photoshop_app, jsx, workdir / "photoshop.jsx")
        if not dpi_report_path.is_file():
            raise RuntimeError("Photoshop non ha prodotto il controllo DPI")
        dpi_report = json.loads(dpi_report_path.read_text(encoding="utf-8"))
        if resize_applied:
            expected_pixels = [target_width_px, target_height_px]
            if dpi_report.get("pixels_after") != expected_pixels:
                raise RuntimeError(
                    f"Dimensioni Photoshop non corrette: "
                    f"{dpi_report.get('pixels_after')} invece di {expected_pixels} px"
                )
        elif dpi_report.get("pixels_before") != dpi_report.get("pixels_after"):
            raise RuntimeError(
                f"La conversione DPI ha cambiato i pixel: "
                f"{dpi_report.get('pixels_before')} -> {dpi_report.get('pixels_after')}"
            )
        if abs(float(dpi_report.get("dpi") or 0) - target_dpi) > 0.01:
            raise RuntimeError(
                f"Risoluzione Photoshop non corretta: {dpi_report.get('dpi')} invece di {target_dpi}"
            )
        return dpi_report

    def resolve_template(self, configured):
        configured = str(configured or "").strip()
        if not configured:
            return None
        direct = Path(configured).expanduser()
        candidates = [direct] if direct.is_absolute() else [self.template_root / direct]
        for candidate in candidates:
            if candidate.is_file():
                resolved = candidate.resolve()
                if direct.is_absolute() or resolved.is_relative_to(self.template_root.resolve()):
                    return resolved
        if not direct.is_absolute() and "/" not in configured and self.template_root.is_dir():
            matches = sorted(path for path in self.template_root.rglob(configured) if path.is_file())
            if len(matches) == 1:
                return matches[0].resolve()
            if len(matches) > 1:
                raise FileNotFoundError(
                    f"Maschera Illustrator ambigua: {configured}. Scegli una sottocartella."
                )
        raise FileNotFoundError(f"Maschera Illustrator non trovata: {configured} (cartella {self.template_root})")

    def execute_hot_folder(self, input_path, config):
        configured_path = Path(str(config.get("agent_path") or "")).expanduser()
        if not configured_path.is_absolute():
            raise RuntimeError("Il percorso hot folder sul Mac deve essere assoluto")

        target_directory = configured_path.resolve(strict=True)
        allowed_roots = [
            root.resolve(strict=True) for root in self.hotfolder_roots if root.is_dir()
        ]
        if not any(
            target_directory == root or root in target_directory.parents
            for root in allowed_roots
        ):
            raise RuntimeError(
                f"Hot folder non autorizzata: {target_directory}"
            )
        if not target_directory.is_dir() or not os.access(target_directory, os.W_OK):
            raise RuntimeError(f"Hot folder non scrivibile: {target_directory}")

        filename = Path(str(config.get("filename") or input_path.name)).name
        target = target_directory / filename
        local_delivery = input_path.with_name(filename)
        if local_delivery != input_path:
            shutil.copyfile(input_path, local_delivery)

        # Il volume Public è montato e autorizzato da Finder. I servizi Python
        # avviati da launchd possono invece ricevere EPERM sui volumi di rete:
        # deleghiamo quindi a Finder la stessa copia già usata operativamente.
        apple_script = (
            f"set sourceFile to POSIX file {json.dumps(str(local_delivery))} as alias\n"
            f"set destinationFolder to POSIX file {json.dumps(str(target_directory) + '/')} as alias\n"
            "tell application \"Finder\"\n"
            "duplicate sourceFile to destinationFolder with replacing\n"
            "end tell\n"
        )
        result = subprocess.run(
            ["/usr/bin/osascript", "-e", apple_script],
            text=True,
            capture_output=True,
            timeout=180,
        )
        if result.returncode:
            # Finder can transiently reject a network-volume copy (for
            # example while the volume is being refreshed). The volume has
            # already been validated and direct file I/O is a safe fallback.
            try:
                temporary_target = target.with_name(
                    f".{target.name}.partial-{os.getpid()}"
                )
                shutil.copyfile(local_delivery, temporary_target)
                os.replace(temporary_target, target)
            except OSError as direct_error:
                if 'temporary_target' in locals() and temporary_target.exists():
                    temporary_target.unlink(missing_ok=True)
                raise RuntimeError(
                    result.stderr.strip() or result.stdout.strip() or
                    f"Finder non ha consegnato il file nella hotfolder: {direct_error}"
                ) from direct_error
        return {
            "destination_code": str(config.get("destination_code") or ""),
            "delivered_to": str(target),
            "delivered_filename": filename,
            "delivery_agent": self.agent_key,
        }

    def resolve_script(self, configured):
        configured = str(configured or "").strip()
        if not configured:
            return None
        direct = Path(configured).expanduser()
        candidates = [direct] if direct.is_absolute() else [self.script_root / direct]
        for candidate in candidates:
            if candidate.is_file() and candidate.suffix.lower() == ".jsx":
                resolved = candidate.resolve()
                if direct.is_absolute() or resolved.is_relative_to(self.script_root.resolve()):
                    return resolved
        if not direct.is_absolute() and "/" not in configured and self.script_root.is_dir():
            matches = sorted(path for path in self.script_root.rglob(configured) if path.is_file())
            if len(matches) == 1:
                return matches[0].resolve()
            if len(matches) > 1:
                raise FileNotFoundError(
                    f"Script Illustrator ambiguo: {configured}. Scegli una sottocartella."
                )
        raise FileNotFoundError(f"Script Illustrator non trovato: {configured} (cartella {self.script_root})")

    def prepare_illustrator_script(self, script, template, input_path):
        source = script.read_text(encoding="utf-8-sig")
        replacements = {
            r"var\s+modello\s*=\s*\$arg1\s*;":
                f"var modello = {self.jsx_string(template.stem)};",
            r"var\s+percorsoTemplate\s*=\s*[^;]+;":
                f"var percorsoTemplate = {self.jsx_string(template)};",
            r"var\s+percorsoImmagine\s*=\s*\$infile\s*;":
                f"var percorsoImmagine = {self.jsx_string(input_path)};",
        }
        for pattern, replacement in replacements.items():
            source, count = re.subn(pattern, replacement, source, count=1)
            if count != 1:
                raise RuntimeError(
                    f"Lo script {script.name} non contiene la variabile attesa: {pattern}"
                )
        return source

    def execute_illustrator(self, input_path, output_path, config, workdir):
        script_mode = str(config.get("script_mode") or "template").strip()
        template = (
            self.resolve_template(config.get("template_path"))
            if script_mode == "template" else None
        )
        script = self.resolve_script(config.get("script_name"))
        pdf_preset = str(config.get("pdf_preset") or "").strip()
        if script and script_mode == "document":
            script_source = script.read_text(encoding="utf-8-sig")
            script_source = re.sub(
                r"^\s*#target[^\r\n]*(?:\r?\n)?", "", script_source,
                flags=re.MULTILINE,
            )
            open_and_place = f"""
var inputFile = new File({self.jsx_string(input_path)});
var documentRef = app.open(inputFile);
{script_source}
documentRef = app.activeDocument;
"""
        elif script:
            if not template:
                raise RuntimeError("Lo script Illustrator richiede una maschera")
            open_and_place = self.prepare_illustrator_script(script, template, input_path)
            open_and_place += "\nvar documentRef = app.activeDocument;\n"
        elif template:
            open_and_place = f"""
var templateFile = new File({self.jsx_string(template)});
var imageFile = new File({self.jsx_string(input_path)});
var documentRef = app.open(templateFile);
var mask = null;
try {{ mask = documentRef.pageItems.getByName("AUTOMATION_MASK"); }} catch (ignored) {{}}
if (!mask && documentRef.pathItems.length > 0) mask = documentRef.pathItems[0];
if (!mask) throw new Error("Nessun tracciato maschera nel file Illustrator");
var placed = documentRef.placedItems.add();
placed.file = imageFile;
var maskBounds = mask.geometricBounds;
var imageBounds = placed.geometricBounds;
var maskWidth = maskBounds[2] - maskBounds[0];
var maskHeight = maskBounds[1] - maskBounds[3];
var imageWidth = imageBounds[2] - imageBounds[0];
var imageHeight = imageBounds[1] - imageBounds[3];
var scale = Math.max(maskWidth / imageWidth, maskHeight / imageHeight) * 100;
placed.resize(scale, scale);
imageBounds = placed.geometricBounds;
placed.position = [
  maskBounds[0] + (maskWidth - (imageBounds[2] - imageBounds[0])) / 2,
  maskBounds[1] - (maskHeight - (imageBounds[1] - imageBounds[3])) / 2
];
var group = documentRef.groupItems.add();
placed.moveToBeginning(group);
mask.moveToBeginning(group);
mask.clipping = true;
group.clipped = true;
documentRef.artboards[0].artboardRect = maskBounds;
"""
        else:
            open_and_place = f"""
var inputFile = new File({self.jsx_string(input_path)});
var documentRef = app.open(inputFile);
"""
        preset_line = (
            f"pdfOptions.pDFPreset = {self.jsx_string(pdf_preset)};" if pdf_preset else ""
        )
        jsx = f"""#target illustrator
app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS;
{open_and_place}
var outputFile = new File({self.jsx_string(output_path)});
var pdfOptions = new PDFSaveOptions();
{preset_line}
documentRef.saveAs(outputFile, pdfOptions);
documentRef.close(SaveOptions.DONOTSAVECHANGES);
"""
        self.execute_jsx(self.illustrator_app, jsx, workdir / "illustrator.jsx")

    @staticmethod
    def wait_for_switch_idle(timeout=300):
        deadline = time.time() + timeout
        announced = False
        while time.time() < deadline:
            result = subprocess.run(["pgrep", "-fl", "osascript"], text=True, capture_output=True)
            competing = [
                line for line in result.stdout.splitlines()
                if "Enfocus/Switch Server" in line or "FinalJavaScript.js" in line
            ]
            if not competing:
                return
            if not announced:
                print("[AdobeAgent] Switch sta usando Adobe; attendo che termini", flush=True)
                announced = True
            time.sleep(2)
        raise TimeoutError("Enfocus Switch sta usando Adobe da oltre 5 minuti")

    @classmethod
    def execute_jsx(cls, app_name, jsx, path):
        cls.wait_for_switch_idle()
        path.write_text(jsx, encoding="utf-8")
        apple_script = (
            f"set jsxFile to POSIX file {json.dumps(str(path))}\n"
            "set jsxCode to read jsxFile\n"
            "with timeout of 300 seconds\n"
            f"tell application {json.dumps(app_name)}\n"
            "activate\n"
            "do javascript jsxCode\n"
            "end tell\n"
            "end timeout\n"
        )
        result = subprocess.run(
            ["osascript", "-e", apple_script],
            text=True,
            capture_output=True,
            timeout=180,
        )
        # Photoshop 2024 può perdere la risposta AppleEvent dopo avere terminato
        # correttamente il JSX (errore -600). Il chiamante verifica comunque che
        # il PDF sia stato realmente creato e non vuoto.
        if result.returncode and "(-600)" not in result.stderr:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"Errore {app_name}")

    def complete(self, task, output_path, config, execution_metadata=None):
        boundary = f"----AutomationAdobe{uuid.uuid4().hex}"
        metadata_values = {"agent": self.agent_key}
        if task["node_type"] == "photoshop":
            metadata_values["real_adobe"] = True
            metadata_values.update({
                "action_set": str(config.get("action_set") or ""),
                "action_name": str(config.get("action_name") or ""),
            })
        elif task["node_type"] == "illustrator":
            metadata_values["real_adobe"] = True
            metadata_values.update({
                "script_mode": str(config.get("script_mode") or "template"),
                "script_name": str(config.get("script_name") or ""),
                "template_path": str(config.get("template_path") or ""),
                "pdf_preset": str(config.get("pdf_preset") or ""),
            })
        metadata_values.update(execution_metadata or {})
        metadata = json.dumps(metadata_values)
        parts = [
            self.form_part(boundary, "worker_id", self.agent_key),
            self.form_part(boundary, "metadata", metadata),
            self.file_part(boundary, "file", output_path),
            f"--{boundary}--\r\n".encode(),
        ]
        self.request(
            f"/api/automation/agent/steps/{task['step_id']}/complete",
            data=b"".join(parts),
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            timeout=180,
        )

    @staticmethod
    def form_part(boundary, name, value):
        return (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n"
            f"{value}\r\n"
        ).encode()

    @staticmethod
    def file_part(boundary, name, path):
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        header = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; "
            f"filename=\"{path.name}\"\r\nContent-Type: {mime}\r\n\r\n"
        ).encode()
        return header + path.read_bytes() + b"\r\n"

    def fail(self, task, error):
        self.last_error = f"{type(error).__name__}: {error}"
        self.request(
            f"/api/automation/agent/steps/{task['step_id']}/fail",
            payload={"worker_id": self.agent_key, "error": self.last_error},
        )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", help="Percorso del file di configurazione")
    parser.add_argument("--server", help="Indirizzo del gestionale")
    parser.add_argument("--name", help="Nome riconoscibile del Mac")
    parser.add_argument("--photoshop-app", help="Nome applicazione Photoshop")
    parser.add_argument("--illustrator-app", help="Nome applicazione Illustrator")
    parser.add_argument("--template-root", help="Cartella maschere Illustrator")
    parser.add_argument("--script-root", help="Cartella script Illustrator")
    parser.add_argument("--pair", metavar="CODICE", help="Associa il Mac con un codice temporaneo")
    parser.add_argument(
        "--scan-photoshop-actions",
        action="store_true",
        help="Legge e salva le azioni disponibili in Photoshop",
    )
    parser.add_argument(
        "--install-service",
        action="store_true",
        help="Installa e avvia l’agente automaticamente all’accesso",
    )
    parser.add_argument("--show-config", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=2)
    args = parser.parse_args()
    agent = AdobeAgent(config_path=args.config)
    if args.server:
        agent.base_url = args.server.rstrip("/")
    if args.name:
        agent.agent_name = args.name
    if args.photoshop_app:
        agent.photoshop_app = args.photoshop_app
    if args.illustrator_app:
        agent.illustrator_app = args.illustrator_app
    if args.template_root:
        agent.template_root = Path(args.template_root).expanduser()
    if args.script_root:
        agent.script_root = Path(args.script_root).expanduser()
    try:
        if args.pair:
            agent.pair(args.pair)
            print(
                f"[AdobeAgent] Mac associato come {agent.agent_name} ({agent.agent_key})",
                flush=True,
            )
            if args.install_service:
                path = agent.install_launch_agent()
                print(f"[AdobeAgent] Avvio automatico installato: {path}", flush=True)
            return
        if args.install_service:
            path = agent.install_launch_agent()
            print(f"[AdobeAgent] Avvio automatico installato: {path}", flush=True)
            return
        if args.scan_photoshop_actions:
            actions = agent.scan_photoshop_actions()
            print(f"[AdobeAgent] {len(actions)} azioni Photoshop rilevate", flush=True)
            return
        if args.show_config:
            safe_config = {
                key: value for key, value in agent.config.items() if key != "token"
            }
            print(
                json.dumps(
                    {
                        **safe_config,
                        "base_url": agent.base_url,
                        "agent_key": agent.agent_key,
                        "agent_name": agent.agent_name,
                        "token_available": bool(agent.token),
                    },
                    indent=2,
                    ensure_ascii=False,
                )
            )
            return
        agent.run(once=args.once, poll_seconds=args.poll_seconds)
    except Exception as error:
        print(f"[AdobeAgent] ERRORE: {type(error).__name__}: {error}", flush=True)
        raise


if __name__ == "__main__":
    main()
