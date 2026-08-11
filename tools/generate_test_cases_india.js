// Generates lib/data/services/test_case_india_v02.dart from
// "Sightline_Detailed Test cases India_V02.xlsx".
const XLSX = require('../node_modules/xlsx');
const fs = require('fs');

const ROOT = '..';
const SRC = `${ROOT}/Sightline_Detailed Test cases India_V02.xlsx`;
const OUT = `${ROOT}/lib/data/services/test_case_india_v02.dart`;

// Detail sheets share one layout: id | name | tireType | tireCond | pressure |
// surface | load | description | link | result | comments.
const DETAIL = [
  { sheet: '1.Test Cases_AQD_CAL',    feature: 'AQD',            activity: 'Calibration', drivetrain: 'Both' },
  { sheet: '2a.AQD_VAL_EV',           feature: 'AQD',            activity: 'Validation',  drivetrain: 'EV' },
  { sheet: '2b.AQD_VAL_ICE',          feature: 'AQD',            activity: 'Validation',  drivetrain: 'ICE' },
  { sheet: '3.Test Cases_Leak_CAL',   feature: 'Leak Detection', activity: 'Calibration', drivetrain: 'Both' },
  { sheet: '4.Test Cases_DFE_CAL',    feature: 'DFE',            activity: 'Calibration', drivetrain: 'Both' },
  { sheet: '5.Test Cases_DFE',        feature: 'DFE',            activity: 'Validation',  drivetrain: 'Both' },
  { sheet: '6.DLE Calibration',       feature: 'DLE',            activity: 'Calibration', drivetrain: 'Both' },
  { sheet: '7.DLE Validation',        feature: 'DLE',            activity: 'Validation',  drivetrain: 'Both' },
  // Winter reuses the DFE numbering in the source workbook — ids get namespaced.
  { sheet: '11.Winter_Test_AQD_DFE',  feature: 'Winter',         activity: 'Validation',  drivetrain: 'Both',
    idPrefix: 'GY.SL.WIN.', commentsCol: 11 },
];
const MATRIX = '3. Vehicle Validation Matrix';

const wb = XLSX.readFile(SRC);
const grid = (name) =>
  XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, defval: '', raw: false });

const txt = (v) => String(v == null ? '' : v).replace(/\s+/g, ' ').trim();
const isId = (v) => /^GY\./i.test(txt(v));

// ── derived metadata ──────────────────────────────────────────────────────
function waterDepthOf(surface, desc) {
  const m = `${surface} ${desc}`.match(/(\d+(?:\.\d+)?)\s*mm/i);
  return m ? `${m[1]}mm` : 'N/A';
}
function loadCategoryOf(load) {
  const s = load.toLowerCase();
  if (s.includes('ballast')) return 'Driver + Ballast';
  if (s.includes('unload')) return 'Unload';
  if (s.includes('full') || s.includes('gvw')) return 'Full';
  if (s.includes('half')) return 'Half';
  if (s.includes('driver')) return 'Driver Only';
  return load ? 'Driver Only' : 'N/A';
}
function surfaceTypeOf(surface, waterDepth) {
  const s = surface.toLowerCase();
  if (!s || s === 'n/a' || s === '-') return 'N/A';
  if (s.includes('jump')) return 'Jump Mu';
  if (s.includes('split')) return 'Split Mu';
  if (s.includes('basalt')) return 'Wet Basalt';
  if (s.includes('ceramic')) return 'Wet Ceramic';
  if (s.includes('snow')) return 'Snow';
  if (s.includes('ice')) return 'Ice';
  if (s.includes('gravel') || s.includes('unpaved')) return 'Gravel';
  if (s.includes('concrete')) return 'Concrete';
  if (s.includes('wet')) return 'Wet Asphalt';
  // "Asphalt - 4mm" means a flooded lane: a water depth implies a wet surface.
  if (waterDepth && waterDepth !== 'N/A') return 'Wet Asphalt';
  if (s.includes('dry')) return 'Dry';
  return surface ? 'Other' : 'N/A';
}

// ── Dart string literal ───────────────────────────────────────────────────
const dq = (v) => {
  const s = String(v == null ? '' : v)
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\$/g, '\\$')
    .replace(/\r?\n/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return `'${s}'`;
};

const cases = [];
const stats = {};
const seen = new Map(); // id -> count, to force uniqueness

function uniqueId(raw) {
  const n = (seen.get(raw) || 0) + 1;
  seen.set(raw, n);
  return n === 1 ? raw : `${raw}#${n}`;
}

// ── detail sheets ─────────────────────────────────────────────────────────
for (const cfg of DETAIL) {
  const rows = grid(cfg.sheet);
  if (!rows.length) { console.log(`!! missing sheet ${cfg.sheet}`); continue; }
  let n = 0, renamed = 0, deduped = 0;
  const cCom = cfg.commentsCol == null ? 10 : cfg.commentsCol;
  for (const r of rows) {
    if (!isId(r[0])) continue;
    let raw = txt(r[0]);
    let remarks = '';
    if (cfg.idPrefix) {
      // Source reuses GY.SL.DFE.* (and emits malformed GY.SL..N) on this sheet.
      const num = raw.match(/(\d+)\s*$/);
      const fixed = cfg.idPrefix + (num ? num[1] : String(n + 1));
      remarks = `Source ID in workbook: ${raw} (${cfg.sheet})`;
      raw = fixed;
      renamed++;
    }
    const id = uniqueId(raw);
    if (id !== raw) deduped++;
    const surface = txt(r[5]);
    const desc = txt(r[7]);
    cases.push({
      testId: id,
      testCasesName: txt(r[1]),
      tireType: txt(r[2]),
      tireCondition: txt(r[3]),
      tirePressure: txt(r[4]),
      roadSurface: surface,
      load: txt(r[6]),
      testDescription: desc,
      testCaseLink: txt(r[8]),
      testResult: txt(r[9]),
      comments: txt(r[cCom]),
      feature: cfg.feature,
      activityType: cfg.activity,
      drivetrain: cfg.drivetrain,
      waterDepth: waterDepthOf(surface, desc),
      loadCategory: loadCategoryOf(txt(r[6])),
      roadSurfaceType: surfaceTypeOf(surface, waterDepthOf(surface, desc)),
      remarks,
    });
    n++;
  }
  stats[cfg.sheet] = { n, renamed, deduped };
}

// ── vehicle validation matrix ─────────────────────────────────────────────
{
  const rows = grid(MATRIX);
  let n = 0, deduped = 0;
  for (const r of rows) {
    if (!isId(r[0])) continue;
    const raw = txt(r[0]);
    const id = uniqueId(raw);
    if (id !== raw) deduped++;
    const site = txt(r[8]);
    cases.push({
      testId: id,
      testCasesName: txt(r[2]),
      tireType: '', tireCondition: '', tirePressure: '',
      roadSurface: site,
      load: '',
      testDescription: txt(r[11]),
      testCaseLink: '', testResult: txt(r[18]), comments: '',
      feature: 'AQD',
      activityType: 'Validation',
      drivetrain: 'Both',
      waterDepth: waterDepthOf(site, txt(r[9])),
      loadCategory: 'N/A',
      roadSurfaceType: surfaceTypeOf(site, waterDepthOf(site, txt(r[9]))),
      reqId: txt(r[1]), asil: txt(r[4]), method: txt(r[7]), testSite: site,
      condition: txt(r[9]), acceptanceCriteria: txt(r[11]),
      safetyMechanism: txt(r[6]), specRef: txt(r[3]), status: txt(r[16]),
      remarks: txt(r[20]),
    });
    n++;
  }
  stats[MATRIX] = { n, renamed: 0, deduped };
}

// ── emit ──────────────────────────────────────────────────────────────────
const lines = [];
lines.push("import '../models/test_case_model.dart';");
lines.push('');
lines.push('// AUTO-GENERATED from "Sightline_Detailed Test cases India_V02.xlsx"');
lines.push('// DO NOT EDIT MANUALLY — regenerate from the workbook instead.');
lines.push('//');
lines.push('// Sheets imported (Public Road & Fault Injection are planning sheets with');
lines.push('// no per-case IDs, so they are not test cases):');
for (const [k, v] of Object.entries(stats)) {
  lines.push(`//   ${k}: ${v.n} cases` +
    (v.renamed ? ` (ids namespaced — source reuses another sheet's numbering)` : '') +
    (v.deduped ? ` (${v.deduped} duplicate id(s) suffixed #n)` : ''));
}
lines.push(`// TOTAL: ${cases.length} cases`);
lines.push('class TestCaseIndiaV02 {');
lines.push('  static List<TestCase> get cases => [');
for (const c of cases) {
  lines.push('    TestCase(');
  lines.push(`      testId: ${dq(c.testId)},`);
  lines.push(`      testCasesName: ${dq(c.testCasesName)},`);
  lines.push(`      tireType: ${dq(c.tireType)}, tireCondition: ${dq(c.tireCondition)},`);
  lines.push(`      tirePressure: ${dq(c.tirePressure)}, roadSurface: ${dq(c.roadSurface)},`);
  lines.push(`      load: ${dq(c.load)},`);
  lines.push(`      testDescription: ${dq(c.testDescription)},`);
  lines.push(`      testCaseLink: ${dq(c.testCaseLink)}, testResult: ${dq(c.testResult)}, comments: ${dq(c.comments)},`);
  lines.push(`      feature: ${dq(c.feature)}, activityType: ${dq(c.activityType)}, drivetrain: ${dq(c.drivetrain)},`);
  lines.push(`      waterDepth: ${dq(c.waterDepth)}, loadCategory: ${dq(c.loadCategory)}, roadSurfaceType: ${dq(c.roadSurfaceType)},`);
  if (c.reqId !== undefined) {
    lines.push(`      reqId: ${dq(c.reqId)}, asil: ${dq(c.asil)}, method: ${dq(c.method)},`);
    lines.push(`      testSite: ${dq(c.testSite)}, condition: ${dq(c.condition)},`);
    lines.push(`      acceptanceCriteria: ${dq(c.acceptanceCriteria)},`);
    lines.push(`      safetyMechanism: ${dq(c.safetyMechanism)}, specRef: ${dq(c.specRef)}, status: ${dq(c.status)},`);
  }
  if (c.remarks) lines.push(`      remarks: ${dq(c.remarks)},`);
  lines.push('    ),');
}
lines.push('  ];');
lines.push('}');

fs.writeFileSync(OUT, lines.join('\n') + '\n', 'utf8');

console.log('--- per sheet ---');
for (const [k, v] of Object.entries(stats)) console.log(`  ${k}: ${v.n}${v.renamed ? ` (renamed ${v.renamed})` : ''}${v.deduped ? ` (dedup ${v.deduped})` : ''}`);
const byFeature = {};
for (const c of cases) {
  const k = `${c.feature} / ${c.activityType} / ${c.drivetrain}`;
  byFeature[k] = (byFeature[k] || 0) + 1;
}
console.log('--- by feature/activity/drivetrain ---');
for (const [k, v] of Object.entries(byFeature).sort()) console.log(`  ${k}: ${v}`);
const dupes = [...seen.entries()].filter(([, n]) => n > 1);
console.log(`TOTAL ${cases.length} cases, ${dupes.length} id(s) needed dedup suffix`);
console.log('wrote', OUT, `(${lines.length} lines)`);
