// Keep a staff dialog independent of the account list's scroll position.
export function openStaffDialog(dialog,{window:viewport,document:page}){
 const previous=page.activeElement,overflow=page.body.style.overflow;
 const left=viewport.scrollX,top=viewport.scrollY;
 const restorePosition=()=>{if(viewport.scrollX!==left||viewport.scrollY!==top)viewport.scrollTo({left,top,behavior:'instant'});};
 page.body.style.overflow='hidden';
 try{dialog.showModal();restorePosition();}catch(error){page.body.style.overflow=overflow;throw error;}
 return()=>{dialog.close();page.body.style.overflow=overflow;if(previous?.isConnected)previous.focus({preventScroll:true});restorePosition();};
}
