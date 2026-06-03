const XLSX = require('xlsx');
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

// Setup directories
const USAGE_DIR = './natrax_usage_sheets';
const REPORTS_DIR = './reconciliation_reports';

if (!fs.existsSync(USAGE_DIR)) {
  fs.mkdirSync(USAGE_DIR);
}
if (!fs.existsSync(REPORTS_DIR)) {
  fs.mkdirSync(REPORTS_DIR);
}

// Helper to convert Excel serial date to YYYY-MM-DD
function serialToDateString(serialDate) {
  if (typeof serialDate === 'string' && serialDate.includes('-')) return serialDate;
  const baseDate = new Date(Date.UTC(1899, 11, 30));
  const date = new Date(baseDate.getTime() + serialDate * 86400000);
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const trackMap = {
  'T1': 'T1', 'High Speed Track': 'T1',
  'T2': 'T2', 'Dynamic Platform Track': 'T2',
  'T3 Wet': 'T3W', 'T3W': 'T3W', 'Straight Wet Braking Track': 'T3W',
  'T3 Dry': 'T3D', 'T3D': 'T3D', 'Straight Dry Braking Track': 'T3D',
  'T4': 'T4', 'Test Hill Track': 'T4',
  'T5': 'T5', 'Accelerated Fatigue Track': 'T5',
  'T6': 'T6', 'Gravel and Off Road Track': 'T6',
  'T7': 'T7', 'Handling Track 4W (1.6 Km)': 'T7', 'Handling Track 4W': 'T7',
  'T8': 'T8', 'Comfort Track': 'T8', 'Gradient Track': 'T8',
  'T9': 'T9', 'Handling Track 2W': 'T9', 'Noise Track': 'T9',
  'T10': 'T10', 'Sustainability Track': 'T10',
  'T11': 'T11', 'Wet Skid Pad Track': 'T11',
  'T12': 'T12', 'Suspension and Traction Track': 'T12',
  'T13': 'T13', 'External Noise Track': 'T13',
  'GR': 'GR', 'General Road Track': 'GR',
  'CC': 'CC', 'Cut and Chip Track': 'CC'
};

const serviceMap = {
  'Refreshment/Lunch': 'Refreshment/Lunch',
  'Lunch': 'Refreshment/Lunch',
  'Refreshment': 'Refreshment/Lunch',
  'Universal EV Charger': 'Universal EV Charger',
  'EV Charger': 'Universal EV Charger',
  'Sand bags 20/50kg': 'Sand bags 20/50kg',
  'Sand bags': 'Sand bags 20/50kg',
  'Unskilled Labour': 'Unskilled Labour',
  'Labour': 'Unskilled Labour',
  'Electricity Charges': 'Electricity Charges',
  'Electricity': 'Electricity Charges',
  'Big Conference Hall': 'Big Conference Hall',
  'Conference Hall': 'Big Conference Hall'
};

function normalizeTrack(trackName) {
  if (!trackName) return 'Unknown';
  const clean = trackName.trim().replace(/\s*\(Exclusive\)/i, '');
  return trackMap[clean] || clean;
}

function normalizeService(serviceName) {
  if (!serviceName) return 'Unknown';
  const clean = serviceName.trim().split(' (')[0];
  return serviceMap[clean] || clean;
}

async function reconcile(fileName) {
  const filePath = path.join(USAGE_DIR, fileName);
  if (!fs.existsSync(filePath)) {
    console.error(`File not found: ${filePath}`);
    return;
  }

  console.log(`\n======================================================`);
  console.log(`🚀 Loading NATRAX Invoice Data from: ${fileName}`);
  console.log(`======================================================`);

  const workbook = XLSX.readFile(filePath);
  
  // Try to find the sheets. If there's multiple sheets, check for 'Detailed Utilisation' or use sheet index 0.
  const sheetName = workbook.SheetNames.includes('Detailed Utilisation') 
    ? 'Detailed Utilisation' 
    : workbook.SheetNames[0];
  
  const sheet = workbook.Sheets[sheetName];
  const natraxRows = XLSX.utils.sheet_to_json(sheet);
  
  console.log(`Found ${natraxRows.length} entries in NATRAX sheet.`);

  if (natraxRows.length === 0) {
    console.log('No data found to reconcile.');
    return;
  }

  // Determine date range of the NATRAX sheet to query our DB
  let minDate = '9999-12-31';
  let maxDate = '0000-01-01';
  const natraxSessionsByDateAndTrack = {};

  for (const row of natraxRows) {
    // Map columns dynamically based on common header names
    const dateVal = row['Date'] || row['Date/Time'] || row['date'];
    const trackVal = row['Track No'] || row['Track'] || row['track'] || row['Track Name'];
    const hrsVal = row['Raw Decimal Hrs'] || row['Duration'] || row['Hours'] || row['hours'] || 0;
    const costVal = row['Final Track Cost'] || row['Cost'] || row['Amount'] || row['cost'] || 0;

    if (!dateVal || !trackVal) continue;

    const dateStr = serialToDateString(dateVal);
    if (dateStr < minDate) minDate = dateStr;
    if (dateStr > maxDate) maxDate = dateStr;

    const trackCode = normalizeTrack(trackVal);
    const key = `${dateStr}_${trackCode}`;

    if (!natraxSessionsByDateAndTrack[key]) {
      natraxSessionsByDateAndTrack[key] = {
        date: dateStr,
        track_code: trackCode,
        track_name: trackVal,
        hours: 0,
        cost: 0,
        entriesCount: 0
      };
    }

    natraxSessionsByDateAndTrack[key].hours += parseFloat(hrsVal);
    natraxSessionsByDateAndTrack[key].cost += parseFloat(costVal);
    natraxSessionsByDateAndTrack[key].entriesCount += 1;
  }

  console.log(`Date range in sheet: ${minDate} to ${maxDate}`);
  console.log('Fetching our logged sessions from Supabase...');

  // Fetch our sessions for the date range
  const { data: ourSessions, error: ourSessionsError } = await supabase
    .from('engineer_sessions')
    .select('*')
    .gte('started_at', `${minDate}T00:00:00+05:30`)
    .lte('started_at', `${maxDate}T23:59:59+05:30`);

  if (ourSessionsError) {
    console.error('Error fetching our sessions:', ourSessionsError);
    return;
  }

  console.log(`Fetched ${ourSessions.length} logged sessions from our database.`);

  // Group our sessions by Date and Track Code
  const ourSessionsByDateAndTrack = {};
  for (const session of ourSessions) {
    const dateStr = session.started_at.split('T')[0];
    const trackCode = normalizeTrack(session.track_code);
    const key = `${dateStr}_${trackCode}`;

    if (!ourSessionsByDateAndTrack[key]) {
      ourSessionsByDateAndTrack[key] = {
        date: dateStr,
        track_code: trackCode,
        track_name: session.track_name,
        hours: 0,
        cost: 0,
        sessionsCount: 0
      };
    }

    ourSessionsByDateAndTrack[key].hours += session.duration_minutes / 60.0;
    ourSessionsByDateAndTrack[key].cost += parseFloat(session.total_cost || 0);
    ourSessionsByDateAndTrack[key].sessionsCount += 1;
  }

  // --- RECONCILIATION COMPARISON ---
  const discrepancies = [];
  const matched = [];
  const allKeys = new Set([
    ...Object.keys(natraxSessionsByDateAndTrack),
    ...Object.keys(ourSessionsByDateAndTrack)
  ]);

  let totalOurCost = 0;
  let totalNatraxCost = 0;

  for (const key of allKeys) {
    const our = ourSessionsByDateAndTrack[key];
    const natrax = natraxSessionsByDateAndTrack[key];

    const date = our ? our.date : natrax.date;
    const track = our ? our.track_code : natrax.track_code;
    const trackName = our ? our.track_name : natrax.track_name;

    const ourHrs = our ? our.hours : 0;
    const natraxHrs = natrax ? natrax.hours : 0;
    const ourCost = our ? our.cost : 0;
    const natraxCost = natrax ? natrax.cost : 0;

    totalOurCost += ourCost;
    totalNatraxCost += natraxCost;

    const hrsVariance = natraxHrs - ourHrs;
    const costVariance = natraxCost - ourCost;

    // Check tolerances (e.g. 0.05 hrs or 10 INR variance is ignorable)
    const hasDiscrepancy = Math.abs(hrsVariance) > 0.05 || Math.abs(costVariance) > 5;

    const resultRow = {
      date,
      track_code: track,
      track_name: trackName,
      ourHrs,
      natraxHrs,
      ourCost,
      natraxCost,
      hrsVariance,
      costVariance,
      status: ''
    };

    if (our && !natrax) {
      resultRow.status = 'MISSING IN NATRAX INVOICE';
      discrepancies.push(resultRow);
    } else if (!our && natrax) {
      resultRow.status = 'UNLOGGED SESSION (Overbilled by NATRAX?)';
      discrepancies.push(resultRow);
    } else if (hasDiscrepancy) {
      resultRow.status = 'MISMATCH (Hours or Cost)';
      discrepancies.push(resultRow);
    } else {
      resultRow.status = 'MATCHED';
      matched.push(resultRow);
    }
  }

  // Generate Markdown report
  const timestamp = new Date().toISOString().replace(/:/g, '-').split('.')[0];
  const reportFileName = `reconciliation_report_${minDate}_to_${maxDate}_${timestamp}.md`;
  const reportPath = path.join(REPORTS_DIR, reportFileName);

  let md = `# NATRAX Automated Reconciliation Audit Report\n`;
  md += `**Audit Period**: ${minDate} to ${maxDate}\n`;
  md += `**Generated At**: ${new Date().toLocaleString()}\n`;
  md += `**Source File**: \`${fileName}\`\n\n`;

  md += `## Summary Dashboard\n\n`;
  md += `| Category | Our Logged (DB) | NATRAX Billed | Variance | Status |\n`;
  md += `| --- | --- | --- | --- | --- |\n`;
  md += `| **Total Cost (INR)** | **₹${totalOurCost.toFixed(2)}** | **₹${totalNatraxCost.toFixed(2)}** | **₹${(totalNatraxCost - totalOurCost).toFixed(2)}** | ${Math.abs(totalNatraxCost - totalOurCost) < 10 ? '✅ MATCHED' : '⚠️ MISMATCH'} |\n\n`;

  md += `### Discrepancy Breakdown\n`;
  md += `- **Matched Items**: ${matched.length}\n`;
  md += `- **Discrepancies Found**: ${discrepancies.length}\n\n`;

  if (discrepancies.length > 0) {
    md += `## ⚠️ Discrepancies Found\n\n`;
    md += `| Date | Track | Our Hrs | NATRAX Hrs | Our Cost | NATRAX Cost | Cost Var | Audit Findings |\n`;
    md += `| --- | --- | --- | --- | --- | --- | --- | --- |\n`;
    for (const d of discrepancies) {
      md += `| ${d.date} | ${d.track_code} (${d.track_name}) | ${d.ourHrs.toFixed(2)} | ${d.natraxHrs.toFixed(2)} | ₹${d.ourCost.toFixed(2)} | ₹${d.natraxCost.toFixed(2)} | **₹${d.costVariance.toFixed(2)}** | \`${d.status}\` |\n`;
    }
    md += `\n`;
  } else {
    md += `## ✅ All Logged Sessions Matched Perfectly!\n\n`;
    md += `No discrepancies were found between our logged track sessions and the NATRAX usage spreadsheet.\n\n`;
  }

  md += `## 📋 Matches Log\n\n`;
  md += `| Date | Track | Hours | Cost | Status |\n`;
  md += `| --- | --- | --- | --- | --- |\n`;
  for (const m of matched) {
    md += `| ${m.date} | ${m.track_code} | ${m.ourHrs.toFixed(2)} | ₹${m.ourCost.toFixed(2)} | Matched |\n`;
  }

  fs.writeFileSync(reportPath, md);

  // Terminal Output
  console.log(`\n======================================================`);
  console.log(`📊 RECONCILIATION SUMMARY`);
  console.log(`======================================================`);
  console.log(`Total Our Cost   : ₹${totalOurCost.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log(`Total NATRAX Cost: ₹${totalNatraxCost.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log(`Cost Variance    : ₹${(totalNatraxCost - totalOurCost).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`);
  console.log(`------------------------------------------------------`);
  console.log(`Matched Entries  : ${matched.length}`);
  console.log(`Discrepancies    : ${discrepancies.length}`);
  console.log(`======================================================`);

  if (discrepancies.length > 0) {
    console.log(`\n🚨 DISCREPANCY LIST (Saved to ${reportPath}):`);
    discrepancies.forEach(d => {
      console.log(` - ${d.date} | Track ${d.track_code}: Our Cost: ₹${d.ourCost.toFixed(2)} vs NATRAX Cost: ₹${d.natraxCost.toFixed(2)} (Var: ₹${d.costVariance.toFixed(2)}) -> ${d.status}`);
    });
  } else {
    console.log('\n✅ SUCCESS: All track sessions matched perfectly!');
  }
}

// Get the latest file from natrax_usage_sheets folder to reconcile
const files = fs.readdirSync(USAGE_DIR).filter(f => f.endsWith('.xlsx') || f.endsWith('.xlsm'));
if (files.length === 0) {
  console.log(`No usage sheets found in ${USAGE_DIR}/`);
  console.log(`Please place NATRAX usage sheets in ${USAGE_DIR}/ folder.`);
} else {
  // Use the specified file name if passed as command line argument, otherwise reconcile the latest
  const argFile = process.argv[2];
  if (argFile && files.includes(argFile)) {
    reconcile(argFile);
  } else {
    // Sort files by modified time and reconcile the latest
    files.sort((a, b) => {
      return fs.statSync(path.join(USAGE_DIR, b)).mtime.getTime() - fs.statSync(path.join(USAGE_DIR, a)).mtime.getTime();
    });
    console.log(`Automatically selecting latest file: ${files[0]}`);
    reconcile(files[0]);
  }
}
