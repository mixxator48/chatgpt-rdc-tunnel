import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const VIDEO_TTL_MS = 30 * 60 * 1000;
const DEFAULT_MAX_VIDEO_MB = 50;
const MEDIA_SESSION_FILE = path.resolve(__dirname, '../../../../../.runtime/media-session.json');

function getMaxVideoBytes() {
    const configuredMb = Number(process.env.RDC_VIDEO_PREVIEW_MAX_MB || DEFAULT_MAX_VIDEO_MB);
    const safeMb = Number.isFinite(configuredMb) && configuredMb > 0
        ? configuredMb
        : DEFAULT_MAX_VIDEO_MB;
    return Math.floor(safeMb * 1024 * 1024);
}

export function getVideoPreviewLimits() {
    return {
        ttlMs: VIDEO_TTL_MS,
        maxVideoBytes: getMaxVideoBytes(),
    };
}

export async function registerPublicMedia(filePath, metadata) {
    let session;
    try {
        session = JSON.parse(await fs.readFile(MEDIA_SESSION_FILE, 'utf8'));
    }
    catch (error) {
        throw new Error(
            'RDC media session is unavailable. Start RDC Local through rc-mcp. ' +
            (error instanceof Error ? error.message : String(error))
        );
    }

    const localBase = String(session.localBase || '').replace(/\/$/, '');
    const publicBase = String(session.publicBase || '').replace(/\/$/, '');
    const secret = String(session.registerSecret || '');

    if (!localBase || !publicBase || !secret) {
        throw new Error('RDC media session file is incomplete. Restart rc-mcp.');
    }

    const response = await fetch(localBase + '/register', {
        method: 'POST',
        headers: {
            'content-type': 'application/json',
            'x-rdc-media-secret': secret,
        },
        body: JSON.stringify({
            path: filePath,
            mimeType: metadata.mimeType,
            fileName: metadata.fileName,
            ttlMs: VIDEO_TTL_MS,
        }),
    });

    let payload = null;
    try {
        payload = await response.json();
    }
    catch {
        // handled below
    }

    if (!response.ok || !payload?.token) {
        throw new Error(
            'Media server registration failed: HTTP ' +
            response.status + ' ' + JSON.stringify(payload)
        );
    }

    return {
        mediaUrl: publicBase + '/media/' + encodeURIComponent(payload.token),
        expiresAt: payload.expiresAt,
        expiresInSeconds: Math.floor(VIDEO_TTL_MS / 1000),
    };
}
