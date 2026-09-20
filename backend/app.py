from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv
import os
from elevenlabs.client import ElevenLabs

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)
CORS(app)

@app.route('/api/elevenlabs/start-conversation', methods=['POST'])
def start_conversation():
    eleven_api_key = os.getenv('ELEVEN_API_KEY')
    if not eleven_api_key:
        return jsonify({'error': 'ElevenLabs API key not configured in backend .env'}), 500

    client = ElevenLabs(api_key=eleven_api_key)

    data = request.json
    agent_id = data.get('agentId')
    user_id = data.get('userId')

    if not agent_id:
        return jsonify({'error': 'Agent ID is required'}), 400

    try:
        # Generate a short-lived conversation token using the ElevenLabs SDK
        response = client.generate_conversation_token(
            agent_id=agent_id,
            user_id=user_id
        )
        return jsonify({'conversationToken': response.conversation_token})
    except Exception as e:
        return jsonify({'error': f'Failed to generate conversation token: {str(e)}'}), 500

if __name__ == '__main__':
    app.run(port=5000, debug=True)
