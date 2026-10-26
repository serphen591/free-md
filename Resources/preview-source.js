import { marked } from 'marked';
import DOMPurify from 'dompurify';
import hljs from 'highlight.js/lib/common';
import katex from 'katex';
import mermaid from 'mermaid';
const escape = s => s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
marked.use({gfm:true,breaks:false, extensions:[
  {name:'mathBlock',level:'block',start:s=>s.indexOf('$$'),tokenizer(s){const m=/^\$\$\s*\n?([\s\S]+?)\n?\$\$(?:\n|$)/.exec(s);if(m)return {type:'mathBlock',raw:m[0],text:m[1]};},renderer(t){return katex.renderToString(t.text,{displayMode:true,throwOnError:false,trust:false});}},
  {name:'mathInline',level:'inline',start:s=>s.indexOf('$'),tokenizer(s){const m=/^\$([^$\n]+?)\$(?!\d)/.exec(s);if(m)return {type:'mathInline',raw:m[0],text:m[1]};},renderer(t){return katex.renderToString(t.text,{displayMode:false,throwOnError:false,trust:false});}}
],renderer:{code(token){const language=(token.lang||'').split(' ')[0];let value=escape(token.text);if(language!=='mermaid' && hljs.getLanguage(language)){try{value=hljs.highlight(token.text,{language}).value;}catch{}}return `<pre><code class="language-${escape(language)} hljs">${value}</code></pre>\n`;}}});
mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'neutral',suppressErrorRendering:true,flowchart:{htmlLabels:false},maxTextSize:50000});
let revision=0;
window.renderMarkdown=async text=>{
  const id=++revision; const article=document.querySelector('article'); const scroll=document.documentElement.scrollTop;
  let parsed;
  try { parsed=marked.parse(text); } catch(e) { article.textContent='预览失败：'+e.message;return; }
  article.innerHTML=DOMPurify.sanitize(parsed,{FORBID_TAGS:['style','script','iframe','object','embed','form','button','video','audio','source'],ADD_TAGS:['input'],ADD_ATTR:['checked','disabled']});
  article.querySelectorAll('input').forEach(input=>{if(input.type==='checkbox')input.disabled=true;else input.remove();});
  // File previews never load remote resources. Only document-relative images are served by the native asset handler.
  article.querySelectorAll('img').forEach(img=>{
    const raw=img.getAttribute('src')||'';
    if(/^data:image\/(png|jpeg|gif|webp);base64,/.test(raw))return;
    if(/^(?:[a-z][a-z\d+.-]*:|\/\/|\/)/i.test(raw)){const hint=document.createElement('span');hint.className='image-hint';hint.textContent='图片 · '+(img.alt||'远程图片未加载');img.replaceWith(hint);return;}
    img.src='mdasset://local/'+raw.split('/').map(p=>encodeURIComponent((()=>{try{return decodeURIComponent(p)}catch{return p}})())).join('/');
    img.onerror=()=>{img.title='找不到本地图片，请确认相对路径位于文档目录内';};
  });
  article.querySelectorAll('a').forEach(a=>a.addEventListener('click',event=>{
    event.preventDefault();const href=a.getAttribute('href')||'';
    if(href.startsWith('#')){try{document.getElementById(decodeURIComponent(href.slice(1)))?.scrollIntoView({behavior:'smooth'});}catch{}return;}
    window.webkit?.messageHandlers?.link?.postMessage(href);
  }));
  article.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach((h,i)=>{h.dataset.heading=i;h.id=h.textContent.toLowerCase().trim().replace(/\s+/g,'-');});
  for(const code of [...article.querySelectorAll('code.language-mermaid')]){
    if(id!==revision)return;
    const host=document.createElement('div');host.className='mermaid';const source=code.textContent;code.parentElement.replaceWith(host);
    try{const result=await mermaid.render(`diagram-${id}-${Math.random().toString(36).slice(2)}`,source);if(id!==revision)return;host.innerHTML=DOMPurify.sanitize(result.svg,{USE_PROFILES:{svg:true,svgFilters:true},ADD_TAGS:['style']});}catch{host.className='diagram-error';host.textContent='流程图语法有误，请检查代码。';}
  }
  if(id===revision)document.documentElement.scrollTop=scroll;
};
window.scrollToHeading=index=>document.querySelector(`[data-heading="${index}"]`)?.scrollIntoView({behavior:'smooth',block:'start'});
window.exportDocument=()=>`<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Markdown 文档</title><!-- preview.css --><!-- vendor/katex.min.css --></head><body><article>${document.querySelector('article').innerHTML}</article></body></html>`;
