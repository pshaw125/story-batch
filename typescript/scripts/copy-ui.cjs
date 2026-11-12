const { copyFileSync } = require('node:fs');
const { join } = require('node:path');
for (const file of ['index.html', 'style.css']) copyFileSync(join(__dirname, '../src/desktop', file), join(__dirname, '../dist/src/desktop', file));
