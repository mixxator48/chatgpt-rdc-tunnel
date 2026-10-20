import { App } from "@modelcontextprotocol/ext-apps";

const video = document.getElementById("video");
const titleEl = document.getElementById("title");
const metaEl = document.getElementById("meta");
const statusEl = document.getElementById("status");
const retryBtn = document.getElementById("retry");
const fullscreenBtn = document.getElementById("fullscreen");
const pipBtn = document.getElementById("pip");

let loadedKey = null;
let connectedPromise = null;
let lastMediaUrl = null;
let lastData = null;

function humanBytes(bytes) {
  if (!Number.isFinite(bytes)) return "";
  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return value.toFixed(i === 0 ? 0 : 1) + " " + units[i];
}

function showStatus(text) {
  statusEl.textContent = text;
  statusEl.classList.remove("hidden");
}

function describeError(error) {
  if (error instanceof Error) return error.name + ": " + error.message;
  if (typeof error === "string") return error;
  try { return JSON.stringify(error); } catch { return String(error); }
}

async function reportWidgetError(message) {
  const caps = app.getHostCapabilities();
  if (!caps?.updateModelContext) return;
  try {
    await app.updateModelContext({
      content: [{
        type: "text",
        text: "RDC video preview failed in the embedded player: " + message
      }]
    });
  } catch {}
}

async function showError(error) {
  console.error(error);
  const message = describeError(error);
  showStatus("Unable to load video: " + message);
  if (lastMediaUrl && lastData) retryBtn.hidden = false;
  await reportWidgetError(message);
}

async function attachRemoteVideo(mediaUrl, data) {
  showStatus("Opening secure media stream...");

  await new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      cleanup();
      reject(new Error("Timed out waiting for video metadata."));
    }, 20000);

    const cleanup = () => {
      clearTimeout(timeout);
      video.removeEventListener("loadedmetadata", onLoadedMetadata);
      video.removeEventListener("error", onError);
    };

    const onLoadedMetadata = () => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve();
    };

    const onError = () => {
      if (settled) return;
      settled = true;
      const mediaError = video.error;
      const codeMap = {
        1: "MEDIA_ERR_ABORTED",
        2: "MEDIA_ERR_NETWORK",
        3: "MEDIA_ERR_DECODE",
        4: "MEDIA_ERR_SRC_NOT_SUPPORTED",
      };
      const code = mediaError?.code || 0;
      const label = codeMap[code] || "MEDIA_ERR_UNKNOWN";
      const detail = mediaError?.message ? ": " + mediaError.message : "";
      cleanup();
      reject(new Error(label + " (" + code + ")" + detail));
    };

    video.addEventListener("loadedmetadata", onLoadedMetadata, { once: true });
    video.addEventListener("error", onError, { once: true });
    video.src = mediaUrl;
    video.load();
  });

  if (!Number.isFinite(video.duration) || video.duration <= 0) {
    throw new Error("Browser parsed the video but reported an invalid duration.");
  }

  video.classList.add("ready");
  statusEl.classList.add("hidden");
  retryBtn.hidden = true;
}

async function loadVideo(result) {
  await connectedPromise;

  const data = result?.structuredContent || {};
  const mediaUrl = result?._meta?.mediaUrl;
  if (!mediaUrl) throw new Error("preview_video result did not include a media URL.");

  const key = mediaUrl;
  if (loadedKey === key) return;
  loadedKey = key;
  lastMediaUrl = mediaUrl;
  lastData = data;
  retryBtn.hidden = true;

  titleEl.textContent = data.title || data.fileName || "Video preview";
  metaEl.textContent = [data.fileName, data.mimeType, humanBytes(Number(data.sizeBytes || 0))]
    .filter(Boolean)
    .join(" · ");

  await attachRemoteVideo(mediaUrl, data);
}

function refreshDisplayButtons() {
  const context = app.getHostContext();
  const modes = context?.availableDisplayModes || [];
  fullscreenBtn.disabled = !modes.includes("fullscreen");
  pipBtn.disabled = !modes.includes("pip");
  fullscreenBtn.title = fullscreenBtn.disabled ? "Fullscreen is not supported by this ChatGPT host" : "";
  pipBtn.title = pipBtn.disabled ? "Picture-in-picture is not supported by this ChatGPT host" : "";
}

const app = new App(
  { name: "RDC Local Video Player", version: "9.0.0" },
  { availableDisplayModes: ["inline", "fullscreen", "pip"] },
  { strict: true },
);

app.ontoolinput = (params) => {
  const args = params?.arguments || {};
  if (args.title) titleEl.textContent = args.title;
  showStatus("Preparing video preview...");
};

app.ontoolresult = (result) => {
  loadVideo(result).catch(showError);
};

app.onhostcontextchanged = () => refreshDisplayButtons();

retryBtn.addEventListener("click", async () => {
  if (!lastMediaUrl || !lastData) return;
  retryBtn.hidden = true;
  try {
    await connectedPromise;
    video.removeAttribute("src");
    video.load();
    await attachRemoteVideo(lastMediaUrl, lastData);
  } catch (error) {
    await showError(error);
  }
});

fullscreenBtn.addEventListener("click", async () => {
  try {
    await connectedPromise;
    await app.requestDisplayMode({ mode: "fullscreen" });
  } catch (error) {
    await showError(error);
  }
});

pipBtn.addEventListener("click", async () => {
  try {
    await connectedPromise;
    await app.requestDisplayMode({ mode: "pip" });
  } catch (error) {
    await showError(error);
  }
});

connectedPromise = app.connect()
  .then(() => refreshDisplayButtons())
  .catch(async (error) => {
    await showError(error);
    throw error;
  });
