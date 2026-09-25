/**
 * Upload or preflight-check existing Steam Workshop items for Total War: WARHAMMER III.
 *
 * Usage: node publish.js [--check] <jobs.json>
 *
 * `jobs.json` is a list of `{ id, contentPath, changeNote }`. Only the content folder and change note are sent, so the title, description, tags,
 * visibility and preview image stay as they are. Each job prints one JSON line: `{ id, ok, error?, needsToAcceptAgreement? }`. A Steam init failure
 * prints `{ fatal }` and exits with code 2. Steam must be running and logged into the account that owns the items.
 */

const fs = require("fs");
const steamworks = require("steamworks.js");

const APP_ID = 1142710;
// An upload with no progress for this long is treated as stalled, and the batch stops so the remaining items stay pending.
const STALL_TIMEOUT_MS = 10 * 60 * 1000;
const PROGRESS_INTERVAL_MS = 2000;
// Steam lookups can hang forever if the client is shutting down, so give up on each one after this long.
const LOOKUP_TIMEOUT_MS = 60 * 1000;
const STATUS_NAMES = ["starting", "preparing config", "preparing content", "uploading", "uploading preview", "committing"];

// //////////////////////////////////////////////////////////////////////////////////////////////////
// //////////////////////////////////////////////////////////////////////////////////////////////////
// Helpers

/**
 * Print one JSON result line for `update.py` to read.
 *
 * @param {Object} entry - Result or fatal message to print.
 */
function emit(entry) {
    process.stdout.write(JSON.stringify(entry) + "\n");
}

/**
 * Describe an error thrown by Steamworks as plain text.
 *
 * @param {unknown} err - The thrown value.
 * @returns {string} The error message.
 */
function errorText(err) {
    return err && err.message ? err.message : String(err);
}

/**
 * Reject a promise that does not settle in time.
 *
 * @param {Promise<T>} promise - The promise to wait for.
 * @param {number} ms - How long to wait in milliseconds.
 * @param {string} message - Error message used on timeout.
 * @returns {Promise<T>} The promise's result, or a rejection after `ms`.
 * @template T
 */
function withTimeout(promise, ms, message) {
    let timer;
    const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${message} within ${ms / 1000} seconds`)), ms);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Check that a Workshop item exists and belongs to the logged-in account.
 *
 * @param {Object} client - The initialized Steamworks client.
 * @param {bigint} itemId - Workshop item ID.
 * @param {bigint} ownSteamId - SteamID64 of the logged-in account.
 * @returns {Promise<string|null>} An error message, or null when the item can be updated.
 */
async function ownershipError(client, itemId, ownSteamId) {
    const item = await withTimeout(client.workshop.getItem(itemId), LOOKUP_TIMEOUT_MS, "Steam did not answer the item lookup");
    if (!item) {
        return "item not found";
    }
    if (item.owner.steamId64 !== ownSteamId) {
        return "not owned by the logged-in account";
    }
    return null;
}

/**
 * Upload one item's content folder and change note, printing progress to stderr and failing if the upload stalls.
 *
 * @param {Object} client - The initialized Steamworks client.
 * @param {bigint} itemId - Workshop item ID.
 * @param {{ id: string, contentPath: string, changeNote: string }} job - The upload job.
 * @returns {Promise<Object>} The Steamworks `UgcResult`. Rejects with an error whose `stalled` flag is set when no progress is made in time.
 */
function uploadItem(client, itemId, job) {
    return new Promise((resolve, reject) => {
        let lastProgress = "";
        let lastChange = Date.now();
        let lastPrinted = "";
        const stallTimer = setInterval(() => {
            if (Date.now() - lastChange > STALL_TIMEOUT_MS) {
                clearInterval(stallTimer);
                const err = new Error(`upload stalled with no progress for ${STALL_TIMEOUT_MS / 60000} minutes`);
                err.stalled = true;
                reject(err);
            }
        }, 5000);
        client.workshop.updateItemWithCallback(
            itemId,
            { contentPath: job.contentPath, changeNote: job.changeNote },
            APP_ID,
            (result) => {
                clearInterval(stallTimer);
                resolve(result);
            },
            (err) => {
                clearInterval(stallTimer);
                reject(err);
            },
            (progress) => {
                const key = `${progress.status}:${progress.progress}`;
                if (key !== lastProgress) {
                    lastProgress = key;
                    lastChange = Date.now();
                }
                const percent = progress.total > 0n ? Number((progress.progress * 100n) / progress.total) : 0;
                const line = `  ${job.id}: ${STATUS_NAMES[progress.status] || "working"} ${percent}%`;
                if (line !== lastPrinted) {
                    lastPrinted = line;
                    process.stderr.write(line + "\n");
                }
            },
            PROGRESS_INTERVAL_MS
        );
    });
}

// //////////////////////////////////////////////////////////////////////////////////////////////////
// //////////////////////////////////////////////////////////////////////////////////////////////////
// Main

/**
 * Run the preflight check or the uploads for every job, one at a time.
 *
 * @returns {Promise<number>} The process exit code.
 */
async function main() {
    const args = process.argv.slice(2);
    const checkOnly = args.includes("--check");
    const jobsPath = args.find((arg) => arg !== "--check");
    const jobs = JSON.parse(fs.readFileSync(jobsPath, "utf8"));

    let client;
    try {
        client = steamworks.init(APP_ID);
    } catch (err) {
        emit({ fatal: `Steam is not running or not logged in (${errorText(err)})` });
        return 2;
    }
    const ownSteamId = client.localplayer.getSteamId().steamId64;

    for (const job of jobs) {
        const itemId = BigInt(job.id);
        try {
            const error = await ownershipError(client, itemId, ownSteamId);
            if (error) {
                emit({ id: job.id, ok: false, error });
                continue;
            }
            if (checkOnly) {
                emit({ id: job.id, ok: true });
                continue;
            }
            const result = await uploadItem(client, itemId, job);
            emit({ id: job.id, ok: true, needsToAcceptAgreement: result.needsToAcceptAgreement });
        } catch (err) {
            emit({ id: job.id, ok: false, error: errorText(err) });
            // Steam may still be working on a stalled update, so do not start another one on top of it.
            if (err && err.stalled) {
                return 3;
            }
        }
    }
    return 0;
}

// Steamworks keeps a callback timer running, so exit explicitly once the jobs are done.
main().then(
    (code) => process.exit(code),
    (err) => {
        emit({ fatal: errorText(err) });
        process.exit(2);
    }
);
