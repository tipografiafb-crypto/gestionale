#!/usr/bin/env python3
"""Agente macOS per eseguire blocchi Photoshop e Illustrator del gestionale."""

import argparse
import json
import mimetypes
import os
import platform
import re
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path


class AdobeAgent:
    def __init__(self):
        self.base_url = os.environ.get("AUTOMATION_BASE_URL", "http://localhost:5010").rstrip("/")
        self.agent_key = os.environ.get("AUTOMATION_AGENT_ID", f"adobe-{socket.gethostname().lower()}")
        self.agent_name = os.environ.get("AUTOMATION_AGENT_NAME", socket.gethostname())
        self.token = os.environ.get("AUTOMATION_AGENT_TOKEN", "")
        self.photoshop_app = os.environ.get("ADOBE_PHOTOSHOP_APP", "Adobe Photoshop 2024")
        self.illustrator_app = os.environ.get("ADOBE_ILLUSTRATOR_APP", "Adobe Illustrator")
        self.template_root = Path(
            os.environ.get("AUTOMATION_TEMPLATE_ROOT", str(Path.home() / "AutomationAdobe" / "templates"))
        )
        self.script_root = Path(
            os.environ.get("AUTOMATION_SCRIPT_ROOT", str(Path.home() / "AutomationAdobe" / "scripts"))
        )
        self.last_error = None

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
        with urllib.request.urlopen(request, timeout=timeout) as response:
            content = response.read()
            return json.loads(content.decode("utf-8")) if content else {}

    def agent_payload(self):
        return {
            "name": self.agent_name,
            "hostname": socket.gethostname(),
            "platform": f"{platform.system()} {platform.mac_ver()[0]}",
            "metadata": {
                "photoshop_app": self.photoshop_app,
                "illustrator_app": self.illustrator_app,
                "template_root": str(self.template_root),
                "script_root": str(self.script_root),
                "illustrator_templates": sorted(path.name for path in self.template_root.glob("*.ai")),
                "illustrator_scripts": sorted(path.name for path in self.script_root.glob("*.jsx")),
                "agent_version": 2,
            },
            "last_error": self.last_error,
        }

    def claim(self):
        response = self.request(
            "/api/automation/agent/claim",
            payload={
                "worker_id": self.agent_key,
                "capabilities": ["photoshop", "illustrator"],
                "agent": self.agent_payload(),
            },
        )
        return response.get("task")

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
                else:
                    raise RuntimeError(f"Tipo Adobe non supportato: {task['node_type']}")

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
        candidates = [direct]
        if not direct.is_absolute():
            candidates.extend([self.template_root / direct, self.template_root / direct.name])
        for candidate in candidates:
            if candidate.is_file():
                return candidate.resolve()
        raise FileNotFoundError(f"Maschera Illustrator non trovata: {configured} (cartella {self.template_root})")

    def resolve_script(self, configured):
        configured = str(configured or "").strip()
        if not configured:
            return None
        direct = Path(configured).expanduser()
        candidates = [direct]
        if not direct.is_absolute():
            candidates.extend([self.script_root / direct, self.script_root / direct.name])
        for candidate in candidates:
            if candidate.is_file() and candidate.suffix.lower() == ".jsx":
                return candidate.resolve()
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
        template = self.resolve_template(config.get("template_path"))
        script = self.resolve_script(config.get("script_name"))
        pdf_preset = str(config.get("pdf_preset") or "").strip()
        if script:
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
        metadata_values = {"agent": self.agent_key, "real_adobe": True}
        if task["node_type"] == "photoshop":
            metadata_values.update({
                "action_set": str(config.get("action_set") or ""),
                "action_name": str(config.get("action_name") or ""),
            })
        elif task["node_type"] == "illustrator":
            metadata_values.update({
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
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--poll-seconds", type=float, default=2)
    args = parser.parse_args()
    agent = AdobeAgent()
    try:
        agent.run(once=args.once, poll_seconds=args.poll_seconds)
    except Exception as error:
        print(f"[AdobeAgent] ERRORE: {type(error).__name__}: {error}", flush=True)
        raise


if __name__ == "__main__":
    main()
