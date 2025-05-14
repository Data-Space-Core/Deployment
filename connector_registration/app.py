from flask import Flask, request, jsonify
import subprocess
import os

app = Flask(__name__)

@app.route('/register-connector', methods=['POST'])
def register_connector():
    # Extract data from the request
    data = request.json
    name = data.get('name')  # Connector name
    security_profile = data.get('security_profile', 'idsc:BASE_SECURITY_PROFILE')  # Default profile
    cert_file = data.get('cert_file')  # Path to the certificate file

    # Validate input
    if not name:
        return jsonify({'error': 'Missing required field: name'}), 400
    if not cert_file:
        return jsonify({'error': 'Missing required field: cert_file'}), 400

    # Path to the register.sh script
    project_root = os.path.abspath(os.path.join(os.getcwd(), '..'))  # Set root to /Users/rfryan/Development/Deployment
    register_script = os.path.join(project_root, 'scripts/register.sh')

    # Check if the script exists and is executable
    if not os.path.isfile(register_script) or not os.access(register_script, os.X_OK):
        return jsonify({'error': f'Script not found or not executable: {register_script}'}), 500

    # Call the register.sh script
    try:
        result = subprocess.run(
            [register_script, name, security_profile, cert_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=project_root  # Set the working directory to the project root
        )
        if result.returncode == 0:
            return jsonify({'message': 'Connector registered successfully', 'output': result.stdout}), 200
        else:
            return jsonify({'error': 'Failed to register connector', 'output': result.stderr}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)