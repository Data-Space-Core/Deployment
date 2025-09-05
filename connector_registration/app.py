from flask import Flask, request, jsonify, send_file
import subprocess, os, re, json

app = Flask(__name__)

# Uploads directory (mounted as a volume)
UPLOAD_FOLDER = '/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  # 10 MB limit

@app.route('/register-connector', methods=['POST'])
def register_connector():
    # 1) Grab form fields
    name = request.form.get('name')
    security_profile = request.form.get('security_profile')

    # 2) Save the uploaded cert bundle
    if 'cert_file' not in request.files:
        return jsonify({"error": "No certificate file provided"}), 400
    cert_file = request.files['cert_file']
    filename = re.sub(r'[^A-Za-z0-9_.-]', '_', cert_file.filename or 'cert.crt')
    cert_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    cert_file.save(cert_path)

    # 3) Run your registration script
    cmd = ["/scripts/register.sh", name or "default-connector", security_profile or "idsc:BASE_SECURITY_PROFILE", cert_path,
           "--config-dir", "/config", "--keys-dir", "/keys"]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        return jsonify({
            "error": "Registration script failed",
            "stderr": result.stderr.strip()
        }), 500

    # 4) Prefer JSON output from the script; fallback to regex line
    registered_cert = None
    try:
        last_line = result.stdout.strip().splitlines()[-1]
        data = json.loads(last_line)
        registered_cert = data.get("client_cert")
    except Exception:
        m = re.search(r"Copied CLIENT_CERT to (/.+\.cert)", result.stdout)
        if m:
            registered_cert = m.group(1)

    # 5) Stream that file back as an attachment
    if registered_cert and os.path.exists(registered_cert):
        return send_file(
            registered_cert,
            as_attachment=True,
            download_name=os.path.basename(registered_cert)
        )
    else:
        return jsonify({
            "error": "Certificate file not found on server",
            "expected_path": registered_cert,
            "output": result.stdout.strip()
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
