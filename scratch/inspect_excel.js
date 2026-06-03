const XLSX = require('xlsx');

try {
  const workbook = XLSX.readFile('NATRAX_Comprehensive_Billing_Final_V15 (1).xlsm');
  console.log('Sheet names:', workbook.SheetNames);
  
  // Let's print some rows of the first few sheets
  workbook.SheetNames.forEach(sheetName => {
    const sheet = workbook.Sheets[sheetName];
    const data = XLSX.utils.sheet_to_json(sheet, { header: 1 });
    console.log(`\n--- Sheet: ${sheetName} ---`);
    console.log(`Total rows: ${data.length}`);
    if (data.length > 0) {
      console.log('Header/First 5 rows:');
      console.log(data.slice(0, 8));
    }
  });
} catch (e) {
  console.error('Error reading excel file:', e);
}
