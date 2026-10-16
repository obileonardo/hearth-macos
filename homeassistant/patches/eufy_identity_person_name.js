/*
 * Show who Eufy recognised: put the familiar face's name into personName.
 *
 * Cameras paired to a HomeBase that the library doesn't treat as a HomeBase 3 (for
 * example the HomeBase Professional, T9000) send "identity person" and "stranger"
 * pushes, but eufy-security-client 4.1.x drops both halves of them:
 *   1. the push parser for indoor and solo cameras never copies nick_name (the
 *      recognised person's name) into person_name, so personName is always "Unknown";
 *   2. those cameras' metadata has no identityPersonDetected or strangerPersonDetected,
 *      so the bridge logs "Invalid Property error" and never fires "person detected".
 * This copies the name and person id across, and gives cameras paired to a base the two
 * missing properties. Home Assistant's sensor.<camera>_person_name then shows the name.
 *
 * Default invocation checks without writing. Only --apply changes files.
 * Apply inside the eufy-security-ws container after an approved rollback plan:
 *     docker cp eufy_identity_person_name.js eufy-security-ws:/tmp/ && \
 *     docker exec eufy-security-ws node /tmp/eufy_identity_person_name.js --apply && \
 *     docker restart eufy-security-ws
 * Safe to run twice. Re-run after updating the eufy-security-ws image.
 */

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
if (args.some(arg => arg.startsWith("--") && arg !== "--apply") || args.filter(arg => arg !== "--apply").length > 1) {
    console.error("usage: node eufy_identity_person_name.js [build-directory] [--apply] (default: read-only check)");
    process.exit(1);
}
const apply = args.includes("--apply");
const root = args.find(arg => arg !== "--apply") || "/usr/src/app/node_modules/eufy-security-client/build";
const marker = "/* identity person name patch */";

const patches = [
    {
        file: path.join(root, "push", "service.js"),
        anchor: "                    normalizedMessage.unique_id = indoorPushData.unique_id;\n",
        insert: `                    ${marker}
                    if ((0, utils_3.isEmpty)(normalizedMessage.person_name)) {
                        const nickName = indoorPushData.nick_name !== undefined && indoorPushData.nick_name !== null ? indoorPushData.nick_name : indoorPushData.person_name;
                        if (typeof nickName === "string" && nickName !== "")
                            normalizedMessage.person_name = nickName;
                    }
                    if (indoorPushData.person_id !== undefined)
                        normalizedMessage.person_id = indoorPushData.person_id;
`,
    },
    {
        file: path.join(root, "http", "device.js"),
        anchor: `        else if (Object.keys(metadata).length === 0) {
            metadata = {
                ...types_1.GenericDeviceProperties,
            };
        }
`,
        insert: `        ${marker}
        if (this.isCamera() &&
            this.getStationSerial() !== this.getSerial() &&
            metadata[types_1.PropertyName.DevicePersonName] !== undefined &&
            metadata[types_1.PropertyName.DeviceIdentityPersonDetected] === undefined) {
            metadata = {
                ...metadata,
                [types_1.PropertyName.DeviceIdentityPersonDetected]: types_1.DeviceIdentityPersonDetectedProperty,
                [types_1.PropertyName.DeviceStrangerPersonDetected]: types_1.DeviceStrangerPersonDetectedProperty,
            };
        }
`,
    },
];

// Check every file before touching any, so a changed library is never half patched.
const pending = [];
for (const patch of patches) {
    if (!fs.existsSync(patch.file)) {
        console.error(`not found, patch not applied: ${patch.file}`);
        process.exit(1);
    }
    const source = fs.readFileSync(patch.file, "utf8");
    if (source.includes(marker)) {
        if (source.split(patch.anchor + patch.insert).length !== 2 ||
            source.replace(patch.anchor + patch.insert, "").includes(patch.anchor)) {
            console.error(`${path.basename(patch.file)}: incomplete patch; nothing applied`);
            process.exit(1);
        }
        console.log("already patched:", patch.file);
        continue;
    }
    if (source.split(patch.anchor).length !== 2) {
        console.error(`${path.basename(patch.file)} has changed shape, patch not applied: ${patch.file}`);
        process.exit(1);
    }
    pending.push({ ...patch, source });
}
if (!apply) {
    for (const patch of pending) console.log("would patch:", path.basename(patch.file));
    console.log(`check complete: ${pending.length} file(s) need changes; use --apply explicitly`);
} else {
    const written = [];
    try {
        for (const patch of pending) {
            if (fs.readFileSync(patch.file, "utf8") !== patch.source) throw new Error("file changed since preflight");
            const updated = patch.source.replace(patch.anchor, patch.anchor + patch.insert);
            atomicWrite(patch.file, updated);
            written.push({ ...patch, updated });
        }
    } catch (error) {
        for (const patch of written.reverse()) {
            if (fs.readFileSync(patch.file, "utf8") === patch.updated) atomicWrite(patch.file, patch.source);
        }
        throw error;
    }
    console.log(`applied: ${written.length} file(s); no service was restarted`);
}

function atomicWrite(file, source) {
    if (!fs.lstatSync(file).isFile()) throw new Error("expected a regular file");
    const temporary = `${file}.hearth-${process.pid}.tmp`;
    try {
        fs.writeFileSync(temporary, source, { flag: "wx", mode: fs.statSync(file).mode & 0o777 });
        fs.renameSync(temporary, file);
    } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
}
