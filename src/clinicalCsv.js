// Spreadsheet-safe text cell. Keep CSV quoting separate from spreadsheet formula interpretation.
export function clinicalCsvCell(value){
 let text=String(value??'');
 if(/^[\s\u200b-\u200f\u202a-\u202e\u2066-\u2069]*[=+\-@]/u.test(text)||/^[\t\r\n]/.test(text))text="'"+text;
 return '"'+text.replace(/"/g,'""')+'"';
}
