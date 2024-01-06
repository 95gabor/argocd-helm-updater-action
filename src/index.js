const { join } = require('path');
const { spawnSync } = require('child_process');

function main() {
    const updater = join(__dirname, 'updater.sh');
    const { status } = spawnSync(updater, { stdio: 'inherit' });

    if (typeof status === 'number') {
        process.exit(status)
    }

    process.exit(1)
}

if (require.main === module) {
    main();
}
