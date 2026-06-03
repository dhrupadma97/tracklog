const XLSX = require('xlsx');
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const env = JSON.parse(fs.readFileSync('env.json', 'utf8'));
const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY);

let ADMIN_UUID;

// Helper to convert Excel date serial and time fraction to IST ISO string
function formatToIST(serialDate, serialTime = 0) {
  const baseDate = new Date(Date.UTC(1899, 11, 30)); // Excel Epoch
  const ms = (serialDate + serialTime) * 86400000;
  const date = new Date(baseDate.getTime() + ms);
  
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  const hr = String(date.getUTCHours()).padStart(2, '0');
  const min = String(date.getUTCMinutes()).padStart(2, '0');
  const sec = String(date.getUTCSeconds()).padStart(2, '0');
  return `${y}-${m}-${d}T${hr}:${min}:${sec}+05:30`;
}

// Helper to convert Excel serial date to YYYY-MM-DD string
function serialToDateString(serialDate) {
  const baseDate = new Date(Date.UTC(1899, 11, 30));
  const date = new Date(baseDate.getTime() + serialDate * 86400000);
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const trackMap = {
  'T1': { code: 'T1', name: 'High Speed Track', rate: 25000 },
  'T1 (Exclusive)': { code: 'T1', name: 'High Speed Track', rate: 180000, booking: 'exclusive' },
  'T2': { code: 'T2', name: 'Dynamic Platform Track', rate: 20000 },
  'T2 (Exclusive)': { code: 'T2', name: 'Dynamic Platform Track', rate: 120000, booking: 'exclusive' },
  'T3 Wet': { code: 'T3W', name: 'Straight Wet Braking Track', rate: 21000 },
  'T3 Dry': { code: 'T3D', name: 'Straight Dry Braking Track', rate: 19000 },
  'T3 (Exclusive)': { code: 'T3W', name: 'Straight Wet Braking Track', rate: 150000, booking: 'exclusive' },
  'T4': { code: 'T4', name: 'Test Hill Track', rate: 8000 },
  'T5': { code: 'T5', name: 'Accelerated Fatigue Track', rate: 14000 },
  'T6': { code: 'T6', name: 'Gravel and Off Road Track', rate: 7500 },
  'T7': { code: 'T7', name: 'Handling Track 4W (1.6 Km)', rate: 15000 },
  'T8': { code: 'T8', name: 'Comfort Track', rate: 10500 },
  'T9': { code: 'T9', name: 'Handling Track 2W', rate: 5000 },
  'T10': { code: 'T10', name: 'Sustainability Track', rate: 6000 },
  'T11': { code: 'T11', name: 'Wet Skid Pad Track', rate: 15000 },
  'T12': { code: 'T12', name: 'Suspension and Traction Track', rate: 6000 },
  'T13': { code: 'T13', name: 'External Noise Track', rate: 14000 },
  'GR': { code: 'GR', name: 'General Road Track', rate: 9000 },
  'CC': { code: 'CC', name: 'Cut and Chip Track', rate: 10500 }
};

const serviceMap = {
  'Refreshment/Lunch (Per Nos)': 'Refreshment/Lunch',
  'Universal EV Charger (Per Unit)': 'Universal EV Charger',
  'Sand bags 20/50kg (Per Nos/Day)': 'Sand bags 20/50kg',
  'Unskilled Labour (Per Day)': 'Unskilled Labour',
  'Electricity Charges (Per Unit)': 'Electricity Charges',
  'Big Conference Hall': 'Big Conference Hall'
};

async function run() {
  console.log('Signing in as admin user to authenticate RLS policies...');
  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email: 'dhrupad_ma@goodyear.com',
    password: 'Dm@nikon12345'
  });
  if (authError) {
    console.error('Failed to authenticate:', authError);
    return;
  }
  console.log('Successfully authenticated as:', authData.user.email);
  ADMIN_UUID = authData.user.id;
  console.log('Dynamic ADMIN_UUID is:', ADMIN_UUID);

  console.log('Reading workbook...');
  const workbook = XLSX.readFile('NATRAX_Comprehensive_Billing_Final_V15 (1).xlsm');


  // --- Step 1: Detailed Utilisation (Raw Sessions) ---
  console.log('Parsing Detailed Utilisation...');
  const detailedSheet = workbook.Sheets['Detailed Utilisation'];
  const rawSessions = XLSX.utils.sheet_to_json(detailedSheet);
  
  console.log(`Found ${rawSessions.length} raw sessions. Processing...`);

  // Map to store created session IDs by date for linking additional services
  const sessionsByDate = {};

  const sessionsToInsert = [];
  for (const row of rawSessions) {
    const dateSerial = row['Date'];
    const trackNo = row['Track No'];
    const inTime = row['In Time'];
    const outTime = row['Out Time'];
    const decimalHrs = row['Raw Decimal Hrs'] || 0;

    if (!dateSerial || !trackNo) continue;

    const mapping = trackMap[trackNo] || { code: trackNo, name: trackNo, rate: 10000 };
    const startedAt = formatToIST(dateSerial, inTime);
    const endedAt = formatToIST(dateSerial, outTime);
    const dateStr = serialToDateString(dateSerial);
    const durationMins = Math.round(decimalHrs * 60);
    const hourlyRate = mapping.rate;
    const totalCost = Math.round(decimalHrs * hourlyRate * 100) / 100;

    const session = {
      engineer_id: ADMIN_UUID,
      track_code: mapping.code,
      track_name: mapping.name,
      vehicle_category: 'below_3_5t',
      booking_type: mapping.booking || 'standard',
      session_status: 'completed',
      started_at: startedAt,
      ended_at: endedAt,
      duration_minutes: durationMins,
      hourly_rate: hourlyRate,
      total_cost: totalCost,
      notes: 'Imported from NATRAX Excel'
    };

    sessionsToInsert.push({ session, dateStr });
  }

  console.log(`Inserting ${sessionsToInsert.length} sessions into Supabase...`);
  // Insert in batches of 100
  const insertedSessions = [];
  for (let i = 0; i < sessionsToInsert.length; i += 100) {
    const batch = sessionsToInsert.slice(i, i + 100).map(s => s.session);
    const batchData = sessionsToInsert.slice(i, i + 100);
    const { data, error } = await supabase.from('engineer_sessions').insert(batch).select('id');
    if (error) {
      console.error(`Error inserting session batch at ${i}:`, error);
      return;
    }
    
    // Save session IDs by date
    data.forEach((inserted, idx) => {
      const dateStr = batchData[idx].dateStr;
      if (!sessionsByDate[dateStr]) {
        sessionsByDate[dateStr] = [];
      }
      sessionsByDate[dateStr].push(inserted.id);
      insertedSessions.push(inserted.id);
    });
  }
  console.log(`Successfully inserted ${insertedSessions.length} sessions!`);

  // --- Step 2: Other Services Log (Additional Services) ---
  console.log('Parsing Other Services Log...');
  const servicesSheet = workbook.Sheets['Other Services Log'];
  const rawServices = XLSX.utils.sheet_to_json(servicesSheet);
  console.log(`Found ${rawServices.length} raw services. Processing...`);

  const servicesToInsert = [];
  // Keep track of total services cost per day for billing summaries
  const servicesCostByDate = {};

  for (const row of rawServices) {
    const dateSerial = row['Date'];
    const serviceCategory = row['Service Category'];
    const qty = row['Qty / Units'] || 0;
    const rate = row['Rate (INR)'] || 0;

    if (!dateSerial || !serviceCategory) continue;

    const dateStr = serialToDateString(dateSerial);
    const serviceName = serviceMap[serviceCategory] || serviceCategory.split(' (')[0];
    const totalCost = qty * rate;

    // Track total services cost per date
    if (!servicesCostByDate[dateStr]) {
      servicesCostByDate[dateStr] = 0;
    }
    servicesCostByDate[dateStr] += totalCost;

    // Find a session on this date to link to
    const sessionIds = sessionsByDate[dateStr];
    let linkedSessionId;
    if (sessionIds && sessionIds.length > 0) {
      linkedSessionId = sessionIds[0]; // Link to first session on that date
    } else {
      // Create a placeholder session for this date
      console.log(`No session found for date ${dateStr}. Creating placeholder...`);
      const startedAt = formatToIST(dateSerial, 0.375); // 9:00 AM
      const endedAt = formatToIST(dateSerial, 0.375); // 9:00 AM
      
      const { data, error } = await supabase.from('engineer_sessions').insert({
        engineer_id: ADMIN_UUID,
        track_code: 'GR',
        track_name: 'General Road Track',
        vehicle_category: 'below_3_5t',
        booking_type: 'standard',
        session_status: 'completed',
        started_at: startedAt,
        ended_at: endedAt,
        duration_minutes: 0,
        hourly_rate: 0,
        total_cost: 0,
        notes: 'Placeholder session for additional services'
      }).select('id').single();

      if (error) {
        console.error('Error creating placeholder session:', error);
        continue;
      }

      linkedSessionId = data.id;
      if (!sessionsByDate[dateStr]) {
        sessionsByDate[dateStr] = [];
      }
      sessionsByDate[dateStr].push(linkedSessionId);
    }

    servicesToInsert.push({
      session_id: linkedSessionId,
      service_name: serviceName,
      quantity: qty,
      rate: rate
    });
  }

  console.log(`Inserting ${servicesToInsert.length} additional services...`);
  for (let i = 0; i < servicesToInsert.length; i += 100) {
    const batch = servicesToInsert.slice(i, i + 100);
    const { error } = await supabase.from('session_additional_services').insert(batch);
    if (error) {
      console.error(`Error inserting service batch at ${i}:`, error);
      return;
    }
  }
  console.log(`Successfully inserted additional services!`);

  // --- Step 3: Daily Track Billing ---
  console.log('Parsing Daily Track Billing summaries...');
  const billingSheet = workbook.Sheets['Daily Track Billing'];
  const rawBilling = XLSX.utils.sheet_to_json(billingSheet);
  console.log(`Found ${rawBilling.length} daily track billing records.`);

  const billingToInsert = [];
  // Keep track of which records have accessories cost assigned
  const assignedAccessoriesByDate = {};

  for (const row of rawBilling) {
    const dateSerial = row['Date'];
    const trackNo = row['Track No'];
    const accHrs = row['Total Accumulated Hrs'] || 0;
    const subjMin = row['Subject to 2hr Min?'] || 'No';
    const billHrs = row['Final Billable Hrs'] || 0;
    const ratePerHr = row['Rate/Hr'] || 0;
    const finalTrackCost = row['Final Track Cost'] || 0;

    if (!dateSerial || !trackNo) continue;

    const dateStr = serialToDateString(dateSerial);
    const mapping = trackMap[trackNo] || { code: trackNo, name: trackNo };

    // Get accessories services cost for this date, assign it to the first track billing row of this date
    let accessoriesCost = 0;
    if (servicesCostByDate[dateStr] && !assignedAccessoriesByDate[dateStr]) {
      accessoriesCost = servicesCostByDate[dateStr];
      assignedAccessoriesByDate[dateStr] = true; // Only assign once per date
    }

    const totalTrackAccCost = finalTrackCost + accessoriesCost;

    billingToInsert.push({
      engineer_id: ADMIN_UUID,
      billing_date: dateStr,
      track_code: mapping.code,
      track_name: mapping.name,
      total_accumulated_hrs: accHrs,
      subject_to_min: subjMin === 'Yes',
      final_billable_hrs: billHrs,
      rate_per_hr: ratePerHr,
      final_track_cost: finalTrackCost,
      accessories_services_cost: accessoriesCost,
      total_track_acc_cost: totalTrackAccCost
    });
  }

  console.log(`Inserting ${billingToInsert.length} daily billing summaries...`);
  for (let i = 0; i < billingToInsert.length; i += 100) {
    const batch = billingToInsert.slice(i, i + 100);
    const { error } = await supabase.from('daily_billing_summaries').insert(batch);
    if (error) {
      console.error(`Error inserting billing batch at ${i}:`, error);
      return;
    }
  }
  console.log(`Successfully inserted daily billing summaries!`);

  // --- Step 4: Monthly Invoice Summary ---
  console.log('Parsing Monthly Invoice Summary...');
  const invoiceSheet = workbook.Sheets['Monthly Invoice Summary'];
  const rawInvoices = XLSX.utils.sheet_to_json(invoiceSheet);
  console.log(`Found ${rawInvoices.length} monthly invoice rows.`);

  const invoicesToInsert = [];
  for (const row of rawInvoices) {
    const billingMonthSerial = row['Billing Month'];
    const trackAccSubtotal = row['Track & Acc Subtotal'];
    const workshopCost = row['Continuous Workshop Cost'] || 0;
    const subtotalExclGst = row['Subtotal (Excl. GST)'];
    const gstRate = 18.00;
    const gstAmount = row['GST @ 18%'];
    const totalAmount = row['Total Invoice Amount'];

    if (!billingMonthSerial || !trackAccSubtotal) continue;

    const monthStr = serialToDateString(billingMonthSerial);

    invoicesToInsert.push({
      engineer_id: ADMIN_UUID,
      billing_month: monthStr,
      track_acc_subtotal: trackAccSubtotal,
      workshop_cost: workshopCost,
      subtotal_excl_gst: subtotalExclGst,
      gst_rate: gstRate,
      gst_amount: gstAmount,
      total_invoice_amount: totalAmount
    });
  }

  console.log(`Inserting ${invoicesToInsert.length} monthly invoices...`);
  const { error: invoiceError } = await supabase.from('monthly_invoices').insert(invoicesToInsert);
  if (invoiceError) {
    console.error('Error inserting monthly invoices:', invoiceError);
    return;
  }
  console.log('Successfully inserted monthly invoices!');
  console.log('\n=======================================');
  console.log('All historical Excel data successfully loaded into Supabase! 🎉');
  console.log('=======================================');
}

run().catch(console.error);
