import React,{useState} from 'react';
const exercises=[
 ['بيع آجل','ما نوع التسديد لفاتورة سيسددها الزبون لاحقاً؟','آجل','نقدي'],
 ['شراء','كيف تسجل 10 عبوات مدفوعة وعبوتين مجانيتين؟','10 كمية و2 بونص','12 عبوة مدفوعة'],
 ['جرد','وجدت 8 عبوات والسجل يقول 10. ماذا تسجّل في العد؟','8 عبوات','10 عبوات'],
 ['مرتجع','ما السجل الذي تربط به مرتجع الزبون؟','فاتورة البيع الأصلية','أحدث فاتورة شراء'],
];
export default function Training() {
 const [answers,setAnswers]=useState({});
 return <div className="adminSettingsCard adminToolsPanel">
  <p>تمارين قصيرة على بيانات اصطناعية.</p>
  {exercises.map(([name,question,right,wrong],i)=><fieldset key={name}>
   <legend>{name}</legend><p>{question}</p>
   {(i%2?[wrong,right]:[right,wrong]).map(answer=><button type="button" className="secondaryAction" key={answer} onClick={()=>setAnswers({...answers,[name]:answer===right})}>{answer}</button>)}
   {name in answers&&<p role="status">{answers[name]?'إجابة صحيحة.':'راجع الإجابة وحاول مرة ثانية.'}</p>}
  </fieldset>)}
  <p>الإجابات الصحيحة {Object.values(answers).filter(Boolean).length} / {exercises.length}</p>
 </div>;
}
