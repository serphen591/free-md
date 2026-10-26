import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
await build({entryPoints:['Resources/preview-source.js'],bundle:true,minify:true,format:'iife',target:'safari15',outfile:'Resources/vendor/preview.js',legalComments:'eof'});
fs.copyFileSync('node_modules/katex/dist/katex.min.css','Resources/vendor/katex.min.css');
fs.cpSync('node_modules/katex/dist/fonts','Resources/vendor/fonts',{recursive:true});
const licenses=[];
function walk(dir){for(const f of fs.readdirSync(dir,{withFileTypes:true})){if(f.name==='node_modules'&&dir.includes('/node_modules/'))continue;const p=path.join(dir,f.name);if(f.isDirectory()){if(f.name.startsWith('@')||fs.existsSync(path.join(p,'package.json')))walk(p);}else if(/^licen[sc]e(?:\.|$)/i.test(f.name)){licenses.push('\n\n===== '+p+' =====\n'+fs.readFileSync(p,'utf8'));}}}
walk('node_modules');
fs.writeFileSync('Resources/ThirdPartyLicenses.txt',licenses.join('\n'));
