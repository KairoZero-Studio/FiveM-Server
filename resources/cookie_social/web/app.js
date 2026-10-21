const root=document.getElementById('root');
const tabs=document.getElementById('tabs');
const search=document.getElementById('search');
const list=document.getElementById('list');
const empty=document.getElementById('empty');
const count=document.getElementById('count');
const sectionMini=document.getElementById('sectionMini');
const sectionTitle=document.getElementById('sectionTitle');
const closeBtn=document.getElementById('closeBtn');

let catalog={};
let favorites={};
let active='favorite';

const meta={
  favorite:{title:'찜',mini:'FAVORITES'},
  dance:{title:'춤',mini:'DANCE'},
  action:{title:'행동',mini:'ACTION'},
  prop:{title:'물건 행동',mini:'PROP ACTION'},
  sync:{title:'같이 행동',mini:'TOGETHER'},
  walk:{title:'걸음걸이',mini:'WALK STYLE'},
  face:{title:'표정',mini:'EXPRESSION'}
};

function post(endpoint,data){
  return fetch('https://'+GetParentResourceName()+'/'+endpoint,{
    method:'POST',
    headers:{'Content-Type':'application/json; charset=UTF-8'},
    body:JSON.stringify(data||{})
  }).then(r=>r.json()).catch(()=>({ok:false}));
}

function rows(){
  const src=Array.isArray(catalog[active])?catalog[active]:[];
  const q=search.value.trim().toLowerCase();
  if(!q)return src;
  return src.filter(r=>
    String(r.label||'').toLowerCase().includes(q)||
    String(r.command||'').toLowerCase().includes(q)
  );
}

function render(){
  document.querySelectorAll('.tab[data-tab]').forEach(b=>b.classList.toggle('active',b.dataset.tab===active));
  const m=meta[active]||meta.favorite;
  sectionMini.textContent=m.mini;
  sectionTitle.textContent=m.title;

  const data=rows();
  count.textContent=String(data.length);
  list.innerHTML='';
  empty.classList.toggle('hidden',data.length!==0);
  list.classList.toggle('hidden',data.length===0);

  data.forEach(row=>{
    const el=document.createElement('div');
    el.className='motion-row';

    const heart=document.createElement('button');
    heart.type='button';
    heart.className='heart'+(favorites[row.id]?' on':'')+(row.favoritable===false?' disabled':'');
    heart.textContent=favorites[row.id]?'♥':'♡';
    heart.addEventListener('click',e=>{
      e.stopPropagation();
      if(row.favoritable===false)return;
      post('favorite',{id:row.id}).then(res=>{
        if(!res.ok)return;
        favorites[row.id]=!!res.on;
        catalog.favorite=res.favorites||[];
        render();
      });
    });

    const copy=document.createElement('div');
    copy.className='copy';
    const name=document.createElement('b');
    name.textContent=row.label||row.command||'모션';
    const cmd=document.createElement('small');
    cmd.textContent=row.command?('/e '+row.command):'선택하여 적용';
    copy.append(name,cmd);

    el.append(heart,copy);

    if(active==='favorite'&&row.sourceCategory){
      const tag=document.createElement('span');
      tag.className='source';
      tag.textContent=(meta[row.sourceCategory]||{}).title||'';
      el.appendChild(tag);
    }

    const arrow=document.createElement('span');
    arrow.className='arrow';
    arrow.textContent='›';
    el.appendChild(arrow);

    el.addEventListener('click',()=>post('play',{id:row.id}));
    list.appendChild(el);
  });
}

tabs.addEventListener('click',e=>{
  const btn=e.target.closest('[data-tab]');
  if(!btn)return;
  active=btn.dataset.tab;
  search.value='';
  render();
});

search.addEventListener('input',render);
closeBtn.addEventListener('click',()=>post('close'));

document.addEventListener('keydown',e=>{
  if(e.key==='Escape'||e.key==='F9'){
    e.preventDefault();
    post('close');
  }
});

window.addEventListener('message',e=>{
  const d=e.data||{};
  if(d.action==='open'){
    catalog=d.catalog||{};
    favorites=d.favorites||{};
    active='favorite';
    search.value='';
    root.classList.remove('hidden');
    render();
    setTimeout(()=>search.focus(),50);
  }
  if(d.action==='close'){
    root.classList.add('hidden');
    list.innerHTML='';
  }
});
