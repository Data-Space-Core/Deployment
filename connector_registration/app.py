from flask import Flask, request, jsonify
import subprocess
import os

app = Flask(__name__)

# Set the correct root directory for keys
UPLOAD_FOLDER = '../uploads/'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)  # Ensure the directory exists
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

@app.route('/register-connector', methods=['POST'])
def register_connector():
    try:
        # Get form data
        name = request.form['name']
        security_profile = request.form['security_profile']

        # Handle file upload
        if 'cert_file' not in request.files:
            return jsonify({"error": "No certificate file provided"}), 400
        cert_file = request.files['cert_file']
        cert_path = os.path.join(app.config['UPLOAD_FOLDER'], cert_file.filename)
        cert_file.save(cert_path)

        # Call the register.sh script with the correct cert_path
        result = subprocess.run(
            ["/scripts/register.sh", name, security_profile, cert_path],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            return jsonify({"error": "Registration failed", "output": result.stderr}), 500

        return jsonify({"message": "Connector registered successfully", "output": result.stdout})

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)