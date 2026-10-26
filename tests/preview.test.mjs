import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!doctype html><html><body><article></article></body></html>',{runScripts:'outside-only',pretendToBeVisual:true,url:'file:///preview.html'});
const {window}=dom;
window.matchMedia=()=>({matches:false,addEventListener(){},removeEventListener(){}});
window.eval(fs.readFileSync('Resources/vendor/preview.js','utf8'));
const article=()=>window.document.querySelector('article');
test('GFM headings, tables, code and math render offline',async()=>{
 await window.renderMarkdown('# 标题\n\n| A | B |\n|---|---|\n|中|文|\n\n```js\nconst x=1;\n```\n\n$$\nE=mc^2\n$$');
 assert.equal(article().querySelector('h1').textContent,'标题');
 assert.ok(article().querySelector('table'));
 assert.ok(article().querySelector('code .hljs-keyword'));
 assert.ok(article().querySelector('.katex'));
});
test('malicious markup is removed and remote images do not load',async()=>{
 await window.renderMarkdown('<script>window.pwned=1</script>\n\n<img src="https://evil.example/pixel" onerror="window.pwned=2">\n\n[click](javascript:alert(1))\n\n<iframe src="https://evil.example"></iframe>');
 assert.equal(window.pwned,undefined);
 assert.equal(article().querySelectorAll('script,iframe,[onerror],[href^="javascript:"]').length,0);
 assert.equal(article().querySelectorAll('img[src^="http"]').length,0);
});
test('relative images map to restricted native scheme, including percent filenames',async()=>{
 await window.renderMarkdown('![local](images/test.png)\n\n<img src="100%.png">');
 assert.equal(article().querySelector('img').getAttribute('src'),'mdasset://local/images/test.png');
 assert.equal(article().querySelectorAll('img')[1].getAttribute('src'),'mdasset://local/100%25.png');
});
test('export keeps rendered content with stylesheet slots',async()=>{
 await window.renderMarkdown('# 导出\n\n正文');
 const html=window.exportDocument(); assert.match(html,/<h1/);assert.match(html,/preview.css/);assert.doesNotMatch(html,/<script/);
});

test("task checkboxes survive sanitization, arbitrary inputs do not", async()=>{await window.renderMarkdown("- [x] done\n- [ ] todo\n\n<input type=text value=bad>");assert.equal(article().querySelectorAll("input[type=checkbox]").length,2);assert.equal(article().querySelectorAll("input:not([type=checkbox])").length,0);assert.ok(article().querySelector("input").disabled);});
