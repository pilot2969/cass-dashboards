#!/usr/bin/env node
/* verify_prod.js — CASS prod-surface gate. Single entry point for every push.
 * usage: node verify_prod.js --mode=prepush [--dir=.]   (local files, pre-commit)
 *        node verify_prod.js --mode=postdeploy --url=https://... (live pages)
 * exit 0 = all checks pass, exit 1 = at least one FAIL. WARN never fails a run.
 */
const fs=require('fs'),path=require('path');
// jsdom lives outside the repo (never committed) and outside /tmp (wiped on sleep)
const {createRequire}=require('module');
const GATE_HOME=process.env.CASS_GATE_HOME||path.join(process.env.HOME||'/root','.cass-gate');
let JSDOM;
try{ JSDOM=require('jsdom').JSDOM; }
catch(e){ JSDOM=createRequire(path.join(GATE_HOME,'node_modules/'))('jsdom').JSDOM; }
const A=process.argv.slice(2);
const arg=(k,d)=>{const h=A.find(x=>x.startsWith('--'+k+'='));return h?h.split('=').slice(1).join('='):d;};
const MODE=arg('mode','prepush'), DIR=path.resolve(arg('dir','.')), URLBASE=arg('url','');
const today=new Date().toISOString().slice(0,10);
const R=[]; const pass=(p,m)=>R.push(['PASS',p,m]); const fail=(p,m)=>R.push(['FAIL',p,m]); const warn=(p,m)=>R.push(['WARN',p,m]);
const daysBetween=(a,b)=>Math.round((new Date(b)-new Date(a))/864e5);

async function loadPage(file){
  const html=fs.readFileSync(path.join(DIR,file),'utf8');
  const dataTxt=fs.readFileSync(path.join(DIR,'data.json'),'utf8');
  const dom=new JSDOM(html,{runScripts:'dangerously',url:'https://gate.invalid/'+encodeURIComponent(file),
    beforeParse(w){ w.fetch=(u)=>{ // serve the real local file the page asks for
                      let rel=decodeURIComponent(String(u).split('?')[0]);
                      try{ rel=decodeURIComponent(new URL(u,'https://gate.invalid/'+encodeURIComponent(file)).pathname).replace(/^\//,''); }catch(e){}
                      let body; try{ body=fs.readFileSync(path.join(DIR,rel),'utf8'); }catch(e){ body=dataTxt; }
                      return Promise.resolve({ok:true,json:()=>Promise.resolve(JSON.parse(body)),text:()=>Promise.resolve(body)}); };
                    w.console.error=()=>{}; w.console.warn=()=>{}; }});
  await new Promise(r=>setTimeout(r,2500));
  return {dom,doc:dom.window.document,data:JSON.parse(dataTxt),html};
}
const txt=s=>String(s||'').replace(/\s+/g,' ').trim();

function proseText(doc){
  const c=doc.body.cloneNode(true);
  c.querySelectorAll('script,style,noscript,template').forEach(n=>n.remove());
  return txt(c.textContent);
}

async function main(){
  const data=JSON.parse(fs.readFileSync(path.join(DIR,'data.json'),'utf8'));

  /* ---------- canonical-source checks (independent of any page) ---------- */
  {
    const P='/space/prediction/', files=fs.readdirSync(P).filter(f=>f.endsWith('.json')&&!f.startsWith('.'));
    const REQ=['card_class','resolution','window_closes','grace_horizon','grace_locked','skill_eligible','public_status'];
    const miss=[];
    for(const f of files){const o=JSON.parse(fs.readFileSync(P+f,'utf8'));
      const gaps=REQ.filter(k=>!(k in o)); if(gaps.length)miss.push(f+':'+gaps.join(','));}
    miss.length?fail('schema.complete',`${miss.length} prediction(s) missing card-schema fields — ${miss.slice(0,3).join(' | ')}`)
               :pass('schema.complete',`all ${files.length} predictions carry the card schema`);
    const und=[]; for(const f of files){const o=JSON.parse(fs.readFileSync(P+f,'utf8'));
      if(['hit','miss'].includes(o.resolution)&&!o.resolution_date)und.push(f);}
    und.length?fail('schema.resolution_dates',`${und.length} resolved card(s) with no resolution_date — ${und.slice(0,3).join(', ')}`)
              :pass('schema.resolution_dates','every scored outcome is dated');
    const unl=[]; for(const f of files){const o=JSON.parse(fs.readFileSync(P+f,'utf8'));
      if(o.grace_locked===true&&!o.grace_locked_date)unl.push(f);}
    unl.length?fail('schema.grace_lock',`${unl.length} card(s) claim a locked grace horizon with no lock date`)
              :pass('schema.grace_lock','grace-lock claims are all dated');
  }

  /* ---------- generator sources must be committed with their output ---------- */
  if(MODE==='prepush'){
    try{
      const {execSync}=require('child_process');
      // sync_data.sh runs this AFTER `git add -A`, so a clean index means the fix
      // is in the commit. Only unstaged (index char ' ') or untracked '??' count.
      const dirty=execSync("git status --porcelain -- '*.py' '*.sh' '*.css' '*.js'",{cwd:DIR,encoding:'utf8'})
        .split('\n').filter(l=>l&&!/node_modules/.test(l))
        .filter(l=>/^\?\?|^ [MDAR]/.test(l));
      dirty.length?fail('source.committed',`generator/source file(s) uncommitted — next rebuild reverts the fix: ${dirty.map(d=>d.replace(/^[A-Z?!]{1,2}\s+/,'')).join(', ')}`)
                  :pass('source.committed','every generator and source file is committed with its output');
    }catch(e){warn('source.committed','git unavailable — could not check source/output parity');}
  }

  /* ---------- data-layer freshness (the root-cause class) ---------- */
  {
    const gen=data.meta&&data.meta.generated;
    const gd=gen&&!isNaN(new Date(gen))?daysBetween(gen,today):null;
    (gd!==null&&gd>1)?fail('data.generated',`data.json stamped ${gen} — ${gd}d behind today`):pass('data.generated',`data.json stamped ${gen}`);
    const ds=(data.mget_ledger||[]).map(e=>String(e.date||'').slice(0,10)).filter(Boolean).sort();
    const nd=ds[ds.length-1];
    (nd&&daysBetween(nd,today)>2)?fail('data.ledger_fresh',`newest ledger entry ${nd} — ${daysBetween(nd,today)}d behind`):pass('data.ledger_fresh',`newest ledger entry ${nd}`);
  }

  /* ---------- generated flow panel (2026-11-09) ----------
     The E panel was hand-built on 11-07 and went stale in two days: a derived number
     that was not derived at build time. Three things are checked so it cannot happen
     again silently: the panel must be as new as the export carrying it; the counts
     must reconcile against the object count it claims; and the declared-dedupe
     arithmetic must close (objects - merged - undated = unique dated), because that
     subtraction IS the series denominator. */
  if(data.flow_panel){
    const fp=data.flow_panel, gen=(data.meta&&data.meta.generated)||data.generated;
    fp.generated===gen?pass('flow_panel.fresh',`flow panel generated ${fp.generated}, same as export`)
      :fail('flow_panel.fresh',`flow panel generated ${fp.generated} but export is ${gen} — panel is stale by design failure`);
    const i=fp.integrity||{};
    const e=fp.panels&&fp.panels.find(p=>p.id==='e-leg-flow');
    const sumSer=e?e.series.reduce((a,b)=>a+(b.raw||0),0):null;
    (e&&sumSer===i.unique_dated)?pass('flow_panel.reconcile',`${sumSer} events in the series = ${i.unique_dated} unique dated`)
      :fail('flow_panel.reconcile',`series sums to ${sumSer} but integrity claims ${i.unique_dated} unique dated`);
    const calc=(i.objects||0)-(i.merged_pairs||[]).length-(i.undated_excluded||[]).length;
    calc===i.unique_dated?pass('flow_panel.dedupe',`${i.objects} objects − ${(i.merged_pairs||[]).length} merged − ${(i.undated_excluded||[]).length} undated = ${calc}`)
      :fail('flow_panel.dedupe',`dedupe arithmetic does not close: ${i.objects} − ${(i.merged_pairs||[]).length} − ${(i.undated_excluded||[]).length} = ${calc}, claims ${i.unique_dated}`);
    const rev=(i.same_date_review||[]).length;
    rev?pass('flow_panel.review',`${rev} same-date pair(s) with differing event_type listed for review, not merged`)
       :pass('flow_panel.review','no same-date double-coding candidates');
  } else {
    fail('flow_panel.present','data.json carries no flow_panel — the E flow panel has no generated source in this export');
  }

  /* ---------- anchor provenance + the legacy gap (pre-cutover only) ---------- */
  {
    // The gap column (computed load vs hand-set live board) is the ONLY external
    // check on the dial numbers and it dies at cutover. Until then it must stay
    // inside ±10 (warn) / ±20 (fail); after cutover it must be gone, not printing "–".
    // Rule: /space/protocol/dial-anchor-provenance.json
    let src=''; try{ src=fs.readFileSync(path.join(DIR,'preview.html'),'utf8'); }catch(e){}
    if(!src){ warn('anchors.source','preview.html not present — anchor checks skipped'); }
    else{
      const m=src.match(/const ANCHORS=(\{[\s\S]*?\n\});/);
      let A=null; try{ A=m?Function('return ('+m[1]+')')():null; }catch(e){}
      if(!A){ fail('anchors.parse','ANCHORS block missing or unparseable in preview.html'); }
      else{
        const bad=[];
        for(const k of ['M','G','E','T']){
          const a=A[k]; if(!a||!Array.isArray(a.anchors)||a.anchors.length!==4){ bad.push(k+':not-4-anchors'); continue; }
          a.anchors.forEach(x=>{
            if(!Array.isArray(x)||x.length<3) return bad.push(k+':malformed');
            if(!Number.isInteger(x[2])||x[2]<0||x[2]>5) bad.push(k+':value-out-of-range:'+x[2]);
            if(txt(x[1]).length<20) bad.push(k+':justification-too-short');
          });
        }
        bad.length?fail('anchors.provenance',`${bad.length} anchor defect(s) — ${bad.slice(0,4).join(', ')}`)
                  :pass('anchors.provenance','all 16 anchors carry a value, a justification and a 0-5 bound');

        // gap discipline: G is an identity (load IS the dial mean, live is the same dial mean)
        const legs=(data.mget&&data.mget.legs)||[];
        let EXC=[]; try{ EXC=JSON.parse(fs.readFileSync(path.join(DIR,'anchor_exceptions.json'),'utf8')).exceptions||[]; }catch(e){ warn('anchors.exceptions','anchor_exceptions.json unreadable — every gap treated as undeclared'); }
        const gapm=[];
        for(const k of ['M','E','T']){
          const a=A[k]; if(!a) continue;
          const load=Math.round(a.anchors.reduce((s,x)=>s+x[2],0)/4*20);
          const live=(legs.find(l=>l.letter===k)||{}).score;
          if(live==null) continue;
          const gap=load-live; gapm.push(k+' '+(gap>0?'+':'')+gap);
          const exc=EXC.find(e=>e.leg===k);
          if(Math.abs(gap)>20){
            if(exc&&exc.frozen_gap===gap&&exc.computed===load&&exc.live===live)
              warn('anchors.gap:'+k,`computed ${load} vs hand-set ${live} — gap ${gap>0?'+':''}${gap} DECLARED in anchor_exceptions.json (${exc.declared}): known-unsupported, not endorsed`);
            else if(exc)
              fail('anchors.gap:'+k,`gap ${gap>0?'+':''}${gap} no longer matches its declaration (${exc.frozen_gap}) — the numbers moved and the declaration is stale`);
            else fail('anchors.gap:'+k,`computed ${load} vs hand-set ${live} — gap ${gap>0?'+':''}${gap}, beyond ±20 and undeclared. Hand-set number is unsupported by its own anchors`);
          }
          else if(Math.abs(gap)>10) warn('anchors.gap:'+k,`computed ${load} vs hand-set ${live} — gap ${gap>0?'+':''}${gap}, beyond ±10`);
        }
        if(gapm.length) pass('anchors.gap',`gap within tolerance — ${gapm.join(', ')} (G excluded: identity, not agreement)`);
        // the vacuous-comparison claim must not reappear
        /counter-example that shows the method works/.test(src)
          ? fail('anchors.g_identity','Governance gap is described as proof the method works — it is an identity and cannot be')
          : pass('anchors.g_identity','Governance gap labelled as identity, not validation');
        // the column must be labelled as a migration artifact, not a live control
        /retires at cutover/i.test(src)
          ? pass('anchors.gap_label','gap column labelled legacy-vs-computed, retires at cutover')
          : warn('anchors.gap_label','gap column not labelled as a cutover artifact');
      }
    }
  }

  /* ---------- render-verified page checks ---------- */
  const pages=fs.readdirSync(DIR).filter(f=>f.endsWith('.html'));
  for(const f of pages){
    let doc,dd;
    CURRENT=f;
    let raw='';
    try{ const r=await loadPage(f); doc=r.doc; dd=r.data; raw=r.html||''; }
    catch(e){ fail('render.throws:'+f,e.message.slice(0,120)); continue; }
    const body=proseText(doc);


    // Q5 hover terms (2026-11-07): every .term must resolve to a key in data.terms, and the
    // definition must actually be injected. data.terms is generated from /space/term, so this
    // is docs.dictionary pointed at the rendering — a tooltip cannot invent its own term.
    {
      const termEls=[...doc.querySelectorAll('.term')];
      if(termEls.length){
        const keys=Object.keys(dd.terms||{});
        const orphan=[...new Set(termEls.map(e=>e.getAttribute('data-term')).filter(k=>!k||!keys.includes(k)))];
        const noDef=termEls.filter(e=>e.getAttribute('data-term')&&keys.includes(e.getAttribute('data-term'))&&!e.getAttribute('data-def')).length;
        orphan.length?fail('docs.hover_terms:'+f,`term(s) with no data.terms entry: ${orphan.join(', ')}`)
          :pass('docs.hover_terms:'+f,`${termEls.length} term(s) resolve to ${keys.length} generated definitions`);
        noDef?fail('docs.hover_terms_def:'+f,`${noDef} term element(s) carry no injected definition`)
             :pass('docs.hover_terms_def:'+f,'every term carries its definition');
      }
    }

    // 1. internal class tokens must never reach prose
    const leaks=[...new Set((body.match(/\bz\d{1,2}\b/g)||[]))];
    leaks.length?fail('prose.no-class-tokens:'+f,`internal token(s) in public text: ${leaks.join(' ')}`)
                :pass('prose.no-class-tokens:'+f,'no internal class tokens in prose');

    // 2. markdown that cannot render inside innerHTML
    const md=(body.match(/\*\*|\[[^\]]+\]\([^)]+\)/g)||[]);
    md.length?fail('prose.no-raw-markdown:'+f,`${md.length} markdown fragment(s) that innerHTML will not render`)
             :pass('prose.no-raw-markdown:'+f,'no unrenderable markdown');

    // 2b. literal \uXXXX escapes in RENDERED prose (added 2026-11-04). A stray escape that
    // never reaches the JS engine shows the reader "100 \u00d7 the mean" instead of a
    // multiplication sign. Only checked against rendered text, so legitimate escapes inside
    // script source (regex classes, '\u25b2' arrows) are untouched — they decode before render.
    const esc=(body.match(/\\u[0-9a-fA-F]{4}/g)||[]);
    esc.length?fail('prose.no-literal-escapes:'+f,`${esc.length} literal escape(s) on the page: ${[...new Set(esc)].join(' ')}`)
             :pass('prose.no-literal-escapes:'+f,'no literal unicode escapes in rendered prose');


    // 3b. direction words must match document order (added 2026-11-04). The panel footer
    // told the reader the Institutional Stress dials were "above" when the Model State
    // panel renders first, so the dials it derives from sit BELOW it. A reader who trusts
    // the sentence looks the wrong way and concludes the two panels contradict. Cheap to
    // check, and it just cost a push.
    if(raw){
      const at=(re)=>{const m=raw.match(re);return m?m.index:null;};
      const headingAt=(name)=>{const m=raw.match(new RegExp('class=zhead>'+name));return m?m.index:null;};
      const mget=headingAt('Model State'), inst=headingAt('Institutional Stress');
      const bad=[];
      if(mget!==null&&inst!==null){
        // "Institutional Stress dials above|below" — the claim is about where that panel sits.
        const re=/Institutional Stress dials? (above|below)/g; let m;
        while((m=re.exec(raw))){
          const says=m[1], really=inst<m.index?'above':'below';
          if(says!==really) bad.push(`"Institutional Stress dials ${says}" at byte ${m.index} — that panel renders ${really}`);
        }
        // "panel above|below Institutional Stress"
        const re2=/panel (above|below) Institutional Stress/g;
        while((m=re2.exec(raw))){
          const says=m[1], really=mget<inst?'above':'below';
          if(says!==really) bad.push(`"panel ${says} Institutional Stress" — Model State renders ${really}`);
        }
      }
      bad.length?fail('prose.panel-direction:'+f,bad.join(' | '))
                :pass('prose.panel-direction:'+f,'direction words match document order');
    }

    // 3. every container the scripts are supposed to fill must be non-empty
    // -grid / -live containers must be filled by their script. -host is legacy
    // in some pages (cards mount to the panel, not the host div) so it only warns.
    const must=[...doc.querySelectorAll('[id$="-live"],[id$="-grid"]')];
    const empty=must.filter(h=>h.innerHTML.trim()==='').map(h=>h.id);
    empty.length?fail('render.containers-filled:'+f,`empty after scripts ran: ${empty.join(', ')}`)
                :pass('render.containers-filled:'+f,`${must.length} live container(s) filled`);
    const dh=[...doc.querySelectorAll('[id$="-host"]')].filter(h=>h.innerHTML.trim()==='').map(h=>h.id);
    if(dh.length)warn('render.legacy-host:'+f,`unused host div(s): ${dh.join(', ')} — cards mount elsewhere; cosmetic`);

    // 4. fallback banners must be suppressed when live data rendered
    const fb=[...doc.querySelectorAll('[id$="-fallback"]')].filter(n=>n.style.display!=='none');
    fb.length?warn('render.fallback-visible:'+f,`${fb.length} fallback banner(s) visible — live render missing`)
             :pass('render.fallback-visible:'+f,'no fallback banners showing');

    if(f==='Internal Telemetry.html' && !(dd&&dd.counts)){
      // A data.json with no counts/institutions is a half-merged artifact, not a
      // data error to be diagnosed page by page — name it once and move on.
      fail('data.shape','data.json has no counts object — generated file was merged instead of restored');
    }
    if(f==='Internal Telemetry.html'&&dd&&dd.counts){
      // 5. counts row must equal the data layer
      const got={items:txt(doc.getElementById('zc-items')?.textContent),preds:txt(doc.getElementById('zc-preds')?.textContent),claims:txt(doc.getElementById('zc-claims')?.textContent)};
      const exp={items:String(dd.counts.items_today),preds:String(dd.counts.tracked_predictions),claims:String(dd.counts.claims_tested)};
      JSON.stringify(got)===JSON.stringify(exp)?pass('counts.match',JSON.stringify(exp))
        :fail('counts.match',`rendered ${JSON.stringify(got)} vs data ${JSON.stringify(exp)}`);

      // 6. gauges
      const dials=doc.querySelectorAll('#zinst-grid svg').length, inst=dd.institutions.institutions.length;
      dials===inst?pass('gauges.live',`${dials} dials = ${inst} institutions`):fail('gauges.live',`${dials} dials rendered vs ${inst} institutions`);
      const rv=txt(doc.getElementById('zinst-reviewed')?.textContent);
      const age=rv&&!isNaN(new Date(rv))?daysBetween(rv,today):null;
      (age!==null&&age>7)?fail('gauges.fresh',`hand review dated ${rv} — ${age}d old (limit 7)`):pass('gauges.fresh',`review dated ${rv}, ${age}d old`);

      // 6b. confirmation indicator + lead delta (2026-11-04). The owner read six recorded
      // hits and could not see one confirmed: the resolution lived in a faint metadata
      // line. A resolved card must now carry a badge in its headline row, and every
      // resolved card with a resolved date must print a lead. Dates that resolve before
      // the card was written are a data error, not a rounding difference.
      if(dd.predictions){
        const res=dd.predictions.filter(p=>['hit','miss','holding'].includes(p.resolution||'unresolved'));
        const badges=doc.querySelectorAll('#zreg .zconf').length;
        badges>=res.length?pass('confirmation.badge',`${badges} badge(s) for ${res.length} resolved card(s)`)
          :fail('confirmation.badge',`${res.length} resolved card(s) but only ${badges} confirmation badge(s) rendered`);
        const wantLead=res.filter(p=>p.resolution_date&&p.date_made&&p.resolution!=='holding').length;
        const gotLead=(doc.getElementById('zreg')?.innerHTML.match(/class="zconflead">\d+d lead/g)||[]).length;
        gotLead>=wantLead?pass('confirmation.lead',`${gotLead} lead delta(s) for ${wantLead} dated resolution(s)`)
          :fail('confirmation.lead',`${wantLead} resolved card(s) have both dates but only ${gotLead} printed a lead`);
        const bad=res.filter(p=>p.resolution_date&&p.date_made&&new Date(p.resolution_date)<new Date(p.date_made)).map(p=>p.basename);
        bad.length?fail('confirmation.dates',`resolved before written: ${bad.join(', ')}`)
                  :pass('confirmation.dates','no card resolves before it was written');
      }

      // 7. ledger
      const rows=doc.querySelectorAll('#ledger-live .row');
      const n=(dd.mget_ledger||[]).length;
      rows.length===n?pass('ledger.live',`${rows.length} rows = ${n} ledger entries`):fail('ledger.live',`${rows.length} rows rendered vs ${n} entries in data.json`);
      const dates=[...rows].map(r=>txt(r.textContent).match(/\d{4}-\d{2}-\d{2}/)?.[0]).filter(Boolean).sort();
      const newestD=dates[dates.length-1];
      (newestD&&daysBetween(newestD,today)>2)?fail('ledger.fresh',`newest rendered entry ${newestD} — ${daysBetween(newestD,today)}d behind`):pass('ledger.fresh',`newest entry ${newestD}`);
      const dateless=[...rows].filter(r=>!/\d{4}-\d{2}-\d{2}/.test(txt(r.textContent))).length;
      dateless?fail('ledger.dated',`${dateless} row(s) with no date`):pass('ledger.dated','every ledger row is dated');
      // The second writer APPENDS to data.json rather than reconciling, so merges
      // republished entries two and three times over: 717 rows carrying 418 events.
      // Rendering duplicates is invisible to a reader and lethal to every count on
      // the page, so dedupe is asserted, not assumed.
      {
        const keys=(dd.mget_ledger||[]).map(e=>e.basename||'');
        const noKey=keys.filter(k=>!k).length;
        const dupes=keys.length-new Set(keys).size;
        (noKey||dupes)?fail('ledger.deduped',`${keys.length} entries — ${dupes} duplicate basename(s), ${noKey} with no basename`)
                      :pass('ledger.deduped',`${keys.length} entries, all unique`);
      }

      // 8. daily read
      const drPanel=[...doc.querySelectorAll('details.zpanel')].find(p=>/Daily Read/i.test(txt(p.querySelector('summary h2, summary .zhead')?.textContent)));
      const cards=drPanel?drPanel.querySelectorAll('div[style*="cursor: pointer"]').length:0;
      const dc=(dd.daily_read?.cards||[]).length;
      cards===dc?pass('dailyread.live',`${cards} cards = ${dc} in data.json`):fail('dailyread.live',`${cards} cards rendered vs ${dc}`);
      const ed=(body.match(/Edition (\d{4}-\d{2}-\d{2})/)||[])[1];
      ed===dd.daily_read?.date?pass('dailyread.edition',`edition stamp ${ed}`):fail('dailyread.edition',`stamp ${ed||'MISSING'} vs data ${dd.daily_read?.date}`);
      daysBetween(dd.daily_read?.date,today)>1?fail('dailyread.fresh',`edition ${dd.daily_read?.date} is ${daysBetween(dd.daily_read?.date,today)}d behind — a dated card stack is the product`):pass('dailyread.fresh',`edition is current (${dd.daily_read?.date})`);

      // 9. register completeness
      const reg=doc.querySelectorAll('details.evt').length;
      reg===dd.counts.tracked_predictions?pass('register.count',`${reg} cards = ${dd.counts.tracked_predictions} tracked`):fail('register.count',`${reg} cards rendered vs ${dd.counts.tracked_predictions} tracked`);
      // class vocabulary: ROLLING added 2026-11-02 with the fifth class (skill_eligible=false).
      // Any new class must be added here in the same push as the class itself, or the
      // cards it labels read as unlabelled and the gate blocks the build.
      const noClass=[...doc.querySelectorAll('details.evt')].filter(c=>!/\b(EVENT|THESIS|MECHANISM|PERSISTENCE|ROLLING)\b/.test(txt(c.textContent))).length;
      noClass?fail('register.class',`${noClass} card(s) with no class label`):pass('register.class','every card states its class');

      // 10. documentation must describe the data it sits above (2026-11-02).
      // The register, the dictionary and the change log are all "technical" surfaces
      // that a reader trusts to be current. Twice today they described a schema the
      // board no longer used, so currency is now asserted rather than assumed.
      // (a) no duplicate card IDs — a second writer appends to predictions[], and
      //     81 entries for 69 cards is what that looks like before it is caught.
      const ids=(dd.predictions||[]).map(p=>p.basename);
      const dupes=ids.filter((b,i)=>ids.indexOf(b)!==i);
      dupes.length?fail('data.predictions_unique',`${ids.length} entries for ${new Set(ids).size} cards — duplicated: ${[...new Set(dupes)].slice(0,4).join(', ')}`)
                  :pass('data.predictions_unique',`${ids.length} predictions, all unique`);

      // (b) every field published on a card has a dictionary entry, found by its
      //     data-field marker. Add a field without documenting it and the push fails.
      const present=[...new Set((dd.predictions||[]).flatMap(p=>Object.keys(p)))];
      const documented=new Set([...doc.querySelectorAll('[data-field]')].map(n=>n.getAttribute('data-field')));
      const undocumented=present.filter(k=>!documented.has(k));
      undocumented.length?fail('docs.dictionary',`field(s) on cards with no dictionary entry: ${undocumented.join(', ')}`)
                         :pass('docs.dictionary',`all ${present.length} card fields documented`);

      // (c) the version in the footer must appear in the change log, and the newest
      //     log entry must be recent — otherwise the footer advertises a build the
      //     log has never heard of, which is how this drifted before.
      const ver=txt(doc.querySelector('.ftver')?.textContent);
      const logged=[...doc.querySelectorAll('.z12')].map(n=>txt(n.textContent).slice(0,120));
      logged.some(t=>ver&&t.includes(ver))?pass('docs.changelog',`footer ${ver} has a change-log entry`)
        :fail('docs.changelog',`footer version ${ver||'MISSING'} appears in no change-log entry`);
      const newestLog=(logged.join(' ').match(/\d{4}-\d{2}-\d{2}/)||[])[0];
      (newestLog&&daysBetween(newestLog,today)>30)?fail('docs.changelog_fresh',`newest change-log entry ${newestLog} — ${daysBetween(newestLog,today)}d behind`)
        :pass('docs.changelog_fresh',`newest change-log entry ${newestLog}`);

      // 10b. the "big questions" section is legacy baked HTML with no renderer —
      // exactly the failure mode that kept this board stale. Its numbers are now
      // asserted against data.json's macro_forecast, so drift surfaces as a FAIL
      // instead of a figure nobody re-reads.
      const mf=dd.macro_forecast;
      if(mf){
        const mfSect=[...doc.querySelectorAll('details')].map(d=>d.textContent).join(' ');
        const ttl=mfSect.includes((mf.title||'').slice(0,30));
        const pct=mfSect.includes(String(Math.round((mf.confidence||0)*100))+'%');
        (ttl&&pct)?pass('bigquestions.match',`macro forecast ${Math.round((mf.confidence||0)*100)}% matches data layer`)
          :fail('bigquestions.match',`big questions section disagrees with data.json macro_forecast (${mf.title||'?'} ${Math.round((mf.confidence||0)*100)}%)`);
      }

      // 11. resolution calendar present and honest
      const cal=[...doc.querySelectorAll('details')].find(d=>/Resolving next 45 days/.test(txt(d.querySelector('summary')?.textContent)));
      cal?pass('calendar.present',txt(cal.querySelector('summary').textContent).slice(0,60)):fail('calendar.present','resolution calendar missing');
    }
  }

  /* ---------- post-deploy: live bytes must equal local bytes ---------- */
  if(MODE==='postdeploy'){
    if(!URLBASE)fail('deploy.url','--url required for postdeploy');
    else{
      const files=fs.readdirSync(DIR).filter(f=>f.endsWith('.html'));
      for(const f of files){
        try{
          const res=await fetch(URLBASE.replace(/\/$/,'')+'/'+encodeURIComponent(f)+'?cb='+Date.now());
          const live=await res.text(), local=fs.readFileSync(path.join(DIR,f),'utf8');
          live===local?pass('deploy.match:'+f,`live ${live.length}b == local`):fail('deploy.match:'+f,`live ${live.length}b != local ${local.length}b — deploy not serving current build`);
        }catch(e){fail('deploy.reach:'+f,e.message.slice(0,100));}
      }
      try{
        const res=await fetch(URLBASE.replace(/\/$/,'')+'/data.json?cb='+Date.now());
        const live=await res.json();
        JSON.stringify(live.counts)===JSON.stringify(data.counts)?pass('deploy.data',`counts ${JSON.stringify(live.counts)}`):fail('deploy.data',`live counts ${JSON.stringify(live.counts)} vs local ${JSON.stringify(data.counts)}`);
      }catch(e){fail('deploy.data',e.message.slice(0,100));}
    }
  }

  /* ---------- report ---------- */
  const w=Math.max(...R.map(r=>r[1].length));
  for(const [s,k,m] of R) console.log(`[${s}] ${k.padEnd(w)}  ${m}`);
  const nf=R.filter(r=>r[0]==='FAIL').length, nw=R.filter(r=>r[0]==='WARN').length;
  console.log(`\n${MODE}: ${R.length-nf-nw} pass, ${nw} warn, ${nf} FAIL`);
  process.exit(nf?1:0);
}
let CURRENT='?';process.on('unhandledRejection',(e)=>{console.log('[FAIL] page.runtime:'+CURRENT+'  script threw during render: '+String(e&&e.message||e).slice(0,140));});
main().catch(e=>{console.error('GATE ERROR',e);process.exit(1);});
