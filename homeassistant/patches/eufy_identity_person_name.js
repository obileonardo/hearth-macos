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
 * Apply inside the eufy-security-ws container, then restart it:
 *     docker cp eufy_identity_person_name.js eufy-security-ws:/tmp/ && \
 *     docker exec eufy-security-ws node /tmp/eufy_identity_person_name.js && \
 *     docker restart eufy-security-ws
 * Safe to run twice. Re-run after updating the eufy-security-ws image.
 */

const fs = require("fs");
const path = require("path");

const root = process.argv[2] || "/usr/src/app/node_modules/eufy-security-client/build";
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
        console.log("already patched:", patch.file);
        continue;
    }
    if (source.split(patch.anchor).length !== 2) {
        console.error(`${path.basename(patch.file)} has changed shape, patch not applied: ${patch.file}`);
        process.exit(1);
    }
    pending.push({ ...patch, source });
}
for (const patch of pending) {
    fs.writeFileSync(patch.file, patch.source.replace(patch.anchor, patch.anchor + patch.insert));
    console.log("patched:", patch.file);
}
