from flask import Flask, request, jsonify, send_file
import subprocess, os, re

app = Flask(__name__)

# Set the correct root directory for uploads
UPLOAD_FOLDER = '../uploads/'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

@app.route('/register-connector', methods=['POST'])
def register_connector():
    # 1) Grab form fields
    name = request.form.get('name')
    security_profile = request.form.get('security_profile')

    # 2) Save the uploaded cert bundle
    if 'cert_file' not in request.files:
        return jsonify({"error": "No certificate file provided"}), 400
    cert_file = request.files['cert_file']
    cert_path = os.path.join(app.config['UPLOAD_FOLDER'], cert_file.filename)
    cert_file.save(cert_path)

    # 3) Run your registration script
    result = subprocess.run(
        ["/scripts/register.sh", name, security_profile, cert_path],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        return jsonify({
            "error": "Registration script failed",
            "stderr": result.stderr.strip()
        }), 500

    # 4) Parse out the new CLIENT_CERT path from stdout
    #
    #    Your script logs a line like:
    #    "Copied CLIENT_CERT to /root/Deployment/keys/clients/XYZ.cert"
    #
    m = re.search(r"Copied CLIENT_CERT to (/.+\.cert)", result.stdout)
    if not m:
        # fallback: just return the raw output
        return jsonify({
            "message": "Registered, but could not locate cert path",
            "output": result.stdout.strip()
        }), 200

    registered_cert = m.group(1)

    # 5) Stream that file back as an attachment
    if os.path.exists(registered_cert):
        return send_file(
            registered_cert,
            as_attachment=True,
            download_name=os.path.basename(registered_cert)
        )
    else:
        return jsonify({
            "error": "Certificate file not found on server",
            "expected_path": registered_cert
        }), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
