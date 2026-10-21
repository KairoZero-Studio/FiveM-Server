const radar=document.getElementById('pmRadar');
const plate=document.getElementById('frontPlate');
const speed=document.getElementById('frontSpeed');

const chase=document.getElementById('chaseHud');
const chaseKind=document.getElementById('chaseKind');
const chaseTime=document.getElementById('chaseTime');
const chaseTarget=document.getElementById('chaseTarget');
const chaseReason=document.getElementById('chaseReason');

const appearance=document.getElementById('appearanceHud');
const appearanceKind=document.getElementById('appearanceKind');
const appearanceTime=document.getElementById('appearanceTime');
const appearanceTarget=document.getElementById('appearanceTarget');

const detention=document.getElementById('detentionHud');
const detentionCharge=document.getElementById('detentionCharge');
const detentionTime=document.getElementById('detentionTime');

const fineReceipt=document.getElementById('fineReceipt');
const receiptFaction=document.getElementById('receiptFaction');
const receiptStatus=document.getElementById('receiptStatus');
const receiptNo=document.getElementById('receiptNo');
const receiptOfficer=document.getElementById('receiptOfficer');
const receiptReason=document.getElementById('receiptReason');
const receiptPayment=document.getElementById('receiptPayment');
const receiptAmount=document.getElementById('receiptAmount');
const receiptIssuedAt=document.getElementById('receiptIssuedAt');
let fineReceiptTimer=null;

function won(value){
  const n=Math.max(0,Math.floor(Number(value)||0));
  return `${n.toLocaleString('ko-KR')}원`;
}

function showFineReceipt(payload){
  const d=payload||{};
  receiptFaction.textContent=d.faction||'경찰청';
  receiptStatus.textContent=d.paid?'납부 완료':'미납';
  receiptStatus.classList.toggle('unpaid',!d.paid);
  receiptNo.textContent=d.receiptNo||'-';
  receiptOfficer.textContent=d.officer||'-';
  receiptReason.textContent=d.reason||'-';
  receiptPayment.textContent=d.paymentMethod|| (d.paid?'납부 완료':'미납');
  receiptAmount.textContent=won(d.amount);
  receiptIssuedAt.textContent=d.issuedAt||'';
  fineReceipt.classList.remove('hidden');
  fineReceipt.classList.remove('fine-receipt-pop');
  void fineReceipt.offsetWidth;
  fineReceipt.classList.add('fine-receipt-pop');
  if(fineReceiptTimer) clearTimeout(fineReceiptTimer);
  fineReceiptTimer=setTimeout(()=>fineReceipt.classList.add('hidden'),9000);
}

function timeText(seconds){
  seconds=Math.max(0,Math.floor(Number(seconds)||0));
  const h=Math.floor(seconds/3600);
  const m=Math.floor((seconds%3600)/60);
  const s=seconds%60;
  if(h>0){
    return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  }
  return `${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
}

window.addEventListener('message',(event)=>{
  const data=event.data||{};

  if(data.action==='pmVisible'){
    radar.classList.toggle('hidden',!data.visible);
    return;
  }

  if(data.action==='pmRadar'){
    if(data.detected){
      plate.textContent=data.plate||'UNKNOWN';
      speed.textContent=`${Math.round(Math.max(0,Number(data.speed)||0))} KM/H`;
    }else{
      plate.textContent='감지 차량 없음';
      speed.textContent='-- KM/H';
    }
    return;
  }

  if(data.action==='chase'){
    const visible=!!data.visible;
    chase.classList.toggle('hidden',!visible);
    radar.classList.toggle('chase-offset',visible);

    if(visible){
      const isEscape=data.kind==='escape';
      const isTarget=data.role==='target';
      chase.classList.toggle('escape',isEscape);
      chaseKind.textContent=isEscape?(isTarget?'도주 중':'도주 추적'):(isTarget?'수배 중':'수배 추적');
      chaseTime.textContent=timeText(data.seconds);
      chaseTarget.textContent=data.target||'- / -';
      chaseReason.textContent=data.reason||'추적 진행 중';
    }
    return;
  }

  if(data.action==='appearance'){
    const visible=!!data.visible;
    appearance.classList.toggle('hidden',!visible);
    if(visible){
      appearanceKind.textContent=data.role==='requester'?'출석 대기':'출석 요구 수락';
      appearanceTime.textContent=timeText(data.seconds);
      appearanceTarget.textContent=data.role==='requester'?(data.target||'-'):'10분 이내 출석 바랍니다.';
    }
    return;
  }

  if(data.action==='appearanceTick'){
    appearanceTime.textContent=timeText(data.seconds);
    if(data.role==='requester')appearanceTarget.textContent=data.target||'-';
    return;
  }

  if(data.action==='detention'){
    detention.classList.toggle('hidden',!data.visible);
    if(data.visible){
      detentionCharge.textContent=data.charge||'-';
      detentionTime.textContent=timeText(data.seconds);
    }
    return;
  }

  if(data.action==='detentionTick'){
    detentionCharge.textContent=data.charge||'-';
    detentionTime.textContent=timeText(data.seconds);
    return;
  }

  if(data.action==='fineReceipt'){
    showFineReceipt(data.data||{});
  }
});
