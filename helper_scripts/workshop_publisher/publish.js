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
 * Check that a Workshop item exists and belongs to the logged-in account.
 *
 * @param {Object} client - The initialized Steamworks client.
 * @param {bigint} itemId - Workshop item ID.
 * @param {bigint} ownSteamId - SteamID64 of the logged-in account.
 * @returns {Promise<string|null>} An error message, or null when the item can be updated.
 */
async function ownershipError(client, itemId, ownSteamId) {
    const item = await client.workshop.getItem(itemId);
    if (!item) {
        return "item not found";
    }
    if (item.owner.steamId64 !== ownSteamId) {
        return "not owned by the logged-in account";
    }
    return null;
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
            const result = await client.workshop.updateItem(itemId, { contentPath: job.contentPath, changeNote: job.changeNote }, APP_ID);
            emit({ id: job.id, ok: true, needsToAcceptAgreement: result.needsToAcceptAgreement });
        } catch (err) {
            emit({ id: job.id, ok: false, error: errorText(err) });
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
