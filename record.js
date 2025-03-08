const axios = require("axios");

const JIBRI_API_URL = process.env.JIBRI_API_URL || "http://82.29.166.156:2222"; // Replace <jibri-ip> with actual IP

async function startRecording(roomName) {
  try {
    console.log(`Attempting to start recording for room: ${roomName}`);
    const response = await axios.post(
      `${JIBRI_API_URL}/jibri/api/v1.0/startRecording`,
      {
        room: roomName,
        callParams: {
          callUrl: `https://jitsi.parentme360.in/${roomName}`,
          email: "recorder@parentme360.in",
          displayName: "ParentMe Recorder",
        },
      },
      {
        headers: { "Content-Type": "application/json" },
        timeout: 5000, // 5-second timeout
      }
    );

    console.log("✅ Recording Started Successfully:", response.data);
  } catch (error) {
    if (error.response) {
      console.error("❌ Recording Failed:", error.response.status);
      console.error("Response Data:", error.response.data);
    } else if (error.request) {
      console.error("❌ No Response from Server:", error.request);
      console.error("Check if Jibri API is running on", JIBRI_API_URL);
    } else {
      console.error("❌ Unexpected Error:", error.message);
    }
    throw error; // Rethrow for higher-level handling
  }
}

// Start recording for room "TestAutoRecord"
startRecording("TestAutoRecord").catch(() => process.exit(1));
