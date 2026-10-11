/* Claude Court — core legal engine.
 * Pure functions and data: the authoritative case record, jurisdictions,
 * decision rules, jury instructions and record digests. No DOM, no network,
 * so it runs in the browser and under `node --test`. */
(function (root) {
"use strict";
const CC = root.CC || (root.CC = {});

/* ---------- seeded randomness ---------- */
CC.mulberry32 = function (seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};
CC.newSeed = () => (Math.floor(Math.random() * 4294967296)) >>> 0;
CC.shuffle = function (arr, rnd) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
};

/* ---------- jurisdictions ---------- */
CC.UNVERIFIED_NOTE = "Built-in summary written from general knowledge. It has not been verified against current law inside this app. Check the primary source before relying on it.";

CC.JURISDICTIONS = {
  "us-federal-criminal": {
    name: "United States — federal criminal trial",
    kinds: ["criminal"],
    factfinder: "jury",
    rule: { type: "unanimous" },
    ruleText: "A verdict must be unanimous. If the jurors cannot agree, the jury is hung and the judge may declare a mistrial.",
    standard: "Proof beyond a reasonable doubt",
    burden: "The prosecution must prove every element of each charge. The defendant does not have to prove anything or testify.",
    evidence: "Federal Rules of Evidence style: evidence must be relevant; it may be excluded if its probative value is substantially outweighed by unfair prejudice; hearsay is generally inadmissible unless an exception applies; exhibits need a foundation showing they are what they claim to be.",
    defenseBurden: "For some affirmative defenses the defendant may carry a burden; the case file must say which. If it does not, the simulation assumes the prosecution must disprove the defense beyond a reasonable doubt once it is raised.",
    references: [
      { label: "Federal Rules of Criminal Procedure, Rule 31(a) — unanimous verdict", verified: false },
      { label: "Federal Rules of Evidence, Rules 401–403 (relevance), 801–807 (hearsay), 901 (authentication)", verified: false },
    ],
    assumptions: ["Twelve jurors are seated."],
  },
  "us-state-criminal": {
    name: "United States — state criminal trial (generic)",
    kinds: ["criminal"],
    factfinder: "jury",
    rule: { type: "unanimous" },
    ruleText: "For serious offenses the verdict must be unanimous. A jury that cannot agree is hung.",
    standard: "Proof beyond a reasonable doubt",
    burden: "The prosecution must prove every element of each charge. The defendant does not have to prove anything or testify.",
    evidence: "Generic state evidence rules modelled on the federal rules: relevance, unfair-prejudice balancing, hearsay with exceptions, authentication. Individual states differ.",
    defenseBurden: "States allocate the burden on affirmative defenses differently. Unless the case file says otherwise, the simulation assumes the prosecution must disprove a raised defense beyond a reasonable doubt.",
    references: [
      { label: "Ramos v. Louisiana (U.S. Supreme Court, 2020) — unanimity required for serious offenses in state trials", verified: false },
    ],
    assumptions: ["A generic state is used; real states differ in jury size for lesser offenses, evidence codes and defense burdens.", "Twelve jurors are seated."],
  },
  "us-federal-civil": {
    name: "United States — federal civil jury trial",
    kinds: ["civil"],
    factfinder: "jury",
    rule: { type: "unanimous" },
    ruleText: "The verdict must be unanimous unless the parties agree otherwise. A jury that cannot agree is hung.",
    standard: "Preponderance of the evidence (more likely than not)",
    burden: "The plaintiff must prove each element of each claim. The defendant carries the burden on its affirmative defenses.",
    evidence: "Federal Rules of Evidence style: relevance, unfair-prejudice balancing, hearsay with exceptions, authentication.",
    defenseBurden: "The defendant must prove affirmative defenses by a preponderance of the evidence unless the case file states another standard.",
    references: [
      { label: "Federal Rules of Civil Procedure, Rule 48 — jury size and unanimity unless the parties stipulate otherwise", verified: false },
    ],
    assumptions: ["Federal civil juries have 6 to 12 members; the simulation seats 12.", "The parties are assumed not to have stipulated to a non-unanimous verdict."],
  },
  "ew-criminal": {
    name: "England & Wales — Crown Court criminal trial",
    kinds: ["criminal"],
    factfinder: "jury",
    rule: { type: "supermajority", min: 10 },
    ruleText: "The jury should try to reach a unanimous verdict. After sufficient deliberation the judge may accept a majority verdict of at least 10 of 12. Without that, the jury is discharged.",
    standard: "The jury must be sure of guilt",
    burden: "The prosecution must prove each element so that the jury is sure. The defendant does not have to prove anything.",
    evidence: "Statutory hearsay framework with admissibility gateways; the court has a discretion to exclude prosecution evidence whose admission would make the proceedings unfair; exhibits need proper provenance.",
    defenseBurden: "Most defenses only need to be raised by evidence; the prosecution must then disprove them so the jury is sure. A few statutory defenses place a burden on the defendant.",
    references: [
      { label: "Juries Act 1974, section 17 — majority verdicts", verified: false },
      { label: "Criminal Justice Act 2003, Part 11 Chapter 2 — hearsay", verified: false },
      { label: "Police and Criminal Evidence Act 1984, section 78 — exclusion of unfair evidence", verified: false },
    ],
    assumptions: ["The simulation treats its deliberation rounds as long enough for the judge to give a majority direction."],
  },
  "ew-civil": {
    name: "England & Wales — civil claim",
    kinds: ["civil"],
    factfinder: "panel",
    rule: { type: "majority" },
    ruleText: "Most civil claims in England & Wales are decided by a judge alone. This simulation uses a 12-member advisory panel deciding by simple majority.",
    standard: "The balance of probabilities",
    burden: "The claimant must prove each element of the claim. The defendant must prove any defense it relies on.",
    evidence: "Civil hearsay is generally admissible, with its weight assessed by the court; relevance and fairness still apply.",
    defenseBurden: "The defendant proves its defenses on the balance of probabilities.",
    references: [
      { label: "Civil Evidence Act 1995 — hearsay admissible in civil proceedings", verified: false },
    ],
    assumptions: ["A 12-member advisory panel replaces the judge as fact-finder; this is a simulation device, not real procedure."],
  },
  "constitutional-generic": {
    name: "Constitutional review (generic court)",
    kinds: ["constitutional"],
    factfinder: "panel",
    rule: { type: "majority" },
    ruleText: "Constitutional questions are normally decided by judges. This simulation uses a 12-member panel deciding by simple majority.",
    standard: "The doctrinal test stated in the case file (for example a scrutiny level or a proportionality test)",
    burden: "The party challenging the measure must establish the interference; the burden of justification is allocated by the test stated in the case file.",
    evidence: "Facts are usually found on a written record; the panel considers only admitted exhibits and testimony.",
    defenseBurden: "Justifications are assessed under the test stated in the case file.",
    references: [],
    assumptions: ["No real constitution is applied; the case file states the rule being tested.", "A 12-member panel deciding by majority is a simulation device."],
  },
  "ethics-panel": {
    name: "Ethical tribunal (no legal system)",
    kinds: ["ethical"],
    factfinder: "panel",
    rule: { type: "majority" },
    ruleText: "A 12-member panel decides by simple majority. There is no legal rule; the panel weighs moral reasons.",
    standard: "The balance of moral reasons, applying the principles stated in the case file",
    burden: "The complainant must show that the conduct was wrong under the stated principles; the respondent may offer justifications.",
    evidence: "No formal admissibility rules; the panel still distinguishes established facts from allegations.",
    defenseBurden: "Justifications and excuses are weighed, not proven to a legal standard.",
    references: [],
    assumptions: ["Outcomes are moral judgments, not legal findings."],
  },
  "unspecified": {
    name: "Unspecified jurisdiction",
    kinds: ["criminal", "civil", "constitutional", "ethical"],
    factfinder: "jury",
    rule: null,
    ruleText: "No jurisdiction was chosen. The simulation assumes a unanimous verdict for criminal cases and a simple majority for all other cases.",
    standard: null,
    burden: "The party bringing the case carries the burden on each element.",
    evidence: "General principles only: relevance, reliability and fairness.",
    defenseBurden: "The simulation assumes the party bringing the case must disprove a raised defense.",
    references: [],
    assumptions: ["Criminal: unanimous verdict of 12, proof beyond a reasonable doubt.", "Other kinds: simple majority of 12, more likely than not."],
  },
};

CC.jurisdiction = (id) => CC.JURISDICTIONS[id] || CC.JURISDICTIONS.unspecified;
CC.jurisdictionsFor = (kind) => Object.entries(CC.JURISDICTIONS).filter(([, j]) => j.kinds.includes(kind)).map(([id, j]) => ({ id, name: j.name }));

CC.decisionRule = function (jurId, kind) {
  const j = CC.jurisdiction(jurId);
  if (j.rule) return Object.assign({ text: j.ruleText, assumption: null }, j.rule);
  return kind === "criminal"
    ? { type: "unanimous", text: j.ruleText, assumption: "Unanimity assumed because no jurisdiction was chosen." }
    : { type: "majority", text: j.ruleText, assumption: "Simple majority assumed because no jurisdiction was chosen." };
};
CC.standardFor = function (jurId, kind) {
  const j = CC.jurisdiction(jurId);
  if (j.standard) return j.standard;
  return { criminal: "Proof beyond a reasonable doubt", civil: "More likely than not", constitutional: "The test stated in the case file", ethical: "The balance of moral reasons" }[kind] || "More likely than not";
};

/* Apply a decision rule to one charge's votes ("yes" | "no" | null per juror). */
CC.applyRule = function (rule, votes) {
  const total = votes.length;
  const yes = votes.filter((v) => v === "yes").length;
  const no = votes.filter((v) => v === "no").length;
  const abstain = total - yes - no;
  let result = "hung", explanation;
  if (rule.type === "unanimous") {
    if (yes === total) result = "yes"; else if (no === total) result = "no";
    explanation = result === "hung"
      ? `Unanimity is required and the jury split ${yes}–${no}${abstain ? ` with ${abstain} not voting` : ""}.`
      : `All ${total} jurors agreed.`;
  } else if (rule.type === "supermajority") {
    if (yes >= rule.min) result = "yes"; else if (no >= rule.min) result = "no";
    explanation = result === "hung"
      ? `At least ${rule.min} of ${total} must agree; the split was ${yes}–${no}.`
      : `${result === "yes" ? yes : no} of ${total} agreed, meeting the ${rule.min}-juror threshold.`;
  } else {
    if (yes > total / 2) result = "yes"; else if (no > total / 2) result = "no";
    explanation = result === "hung"
      ? `A simple majority of ${total} is needed; the split was ${yes}–${no}.`
      : `${result === "yes" ? yes : no} of ${total} formed a majority.`;
  }
  return { result, yes, no, abstain, explanation };
};

CC.labelsFor = function (kind, factfinder) {
  const hung = factfinder === "jury" ? "HUNG JURY" : "NO MAJORITY";
  return ({
    criminal: { yes: "GUILTY", no: "NOT GUILTY", hung },
    civil: { yes: "LIABLE", no: "NOT LIABLE", hung },
    constitutional: { yes: "VIOLATION FOUND", no: "NO VIOLATION", hung },
    ethical: { yes: "UPHELD", no: "REJECTED", hung },
  })[kind] || { yes: "YES", no: "NO", hung };
};
CC.sidesFor = function (kind, jurId) {
  const uk = /^ew-/.test(jurId || "");
  return ({
    criminal: { pros: "Prosecution", def: "Defense" },
    civil: { pros: uk ? "Claimant" : "Plaintiff", def: "Defendant" },
    constitutional: { pros: "Petitioner", def: "Respondent" },
    ethical: { pros: "Complainant", def: "Respondent" },
  })[kind] || { pros: "Prosecution", def: "Defense" };
};

/* ---------- juror reasoning profiles ---------- */
CC.PROFILES = [
  { id: "analytical", name: "Analytical", method: "Breaks each charge into its elements and requires specific record items for every element before finding it proven." },
  { id: "skeptical", name: "Skeptical", method: "Tests every inference for innocent or alternative explanations and gives little weight to uncorroborated claims, whichever side makes them." },
  { id: "detail", name: "Detail-oriented", method: "Reconstructs the timeline, checks quantities, times and distances, and looks for internal inconsistencies." },
  { id: "instructions", name: "Instruction-focused", method: "Applies the court's instructions and stated legal rules literally and refuses to use outside law or personal views of what the law should be." },
  { id: "credibility", name: "Credibility-attentive", method: "Weighs each witness's opportunity to observe, bias or interest, consistency with prior statements, and corroboration." },
  { id: "probabilistic", name: "Probabilistic", method: "Estimates how likely each competing explanation is and compares the result with the standard of proof." },
  { id: "burden", name: "Burden-focused", method: "At each step asks whether the party carrying the burden has actually carried it, and resolves genuine doubt against that party." },
  { id: "narrative", name: "Narrative-coherence", method: "Compares the completeness and coherence of the competing accounts and identifies gaps each side has not explained." },
  { id: "forensic", name: "Forensic", method: "Concentrates on physical, documentary and expert evidence: chain of custody, method, error rates and what the evidence can and cannot show." },
  { id: "practical", name: "Practical experience", method: "Tests claims against ordinary experience of how people behave, while noting where ordinary experience may mislead." },
  { id: "procedural", name: "Procedural", method: "Keeps track of what was excluded, struck or admitted for a limited purpose and makes sure only proper evidence is used." },
  { id: "steelman", name: "Steelman", method: "Before deciding, writes the strongest version of the side they currently disagree with and checks whether it survives." },
];
CC.profile = (id) => CC.PROFILES.find((p) => p.id === id) || CC.PROFILES[0];
CC.OPENNESS = { low: "Changes position only when shown record evidence or a reasoning error they had missed.", medium: "Changes position when an argument directly answers their main reason.", high: "Readily reconsiders when a well-supported argument raises real doubt about their reasoning." };

CC.defaultJurors = function (seed) {
  const rnd = CC.mulberry32(seed ^ 0x9e3779b9);
  const order = CC.shuffle(CC.PROFILES.map((p) => p.id), rnd);
  return order.map((pid, i) => {
    const r = rnd();
    return { n: i + 1, profile: pid, openness: r < 0.3 ? "low" : r < 0.75 ? "medium" : "high", user: false, provisional: null, final: null, rounds: [] };
  });
};

/* ---------- case normalization (the authoritative record) ---------- */
const str = (x, max) => String(x == null ? "" : x).replace(/\s+/g, " ").trim().slice(0, max || 600);
const txt = (x, max) => String(x == null ? "" : x).trim().slice(0, max || 2000);
const arr = (a) => (Array.isArray(a) ? a : []);
CC.str = str;
CC.txt = txt;

function uniqueIds(items, prefix, pattern) {
  const seen = new Set();
  let n = 1;
  items.forEach((it) => {
    let id = str(it.id, 16).toUpperCase();
    if (!id || (pattern && !pattern.test(id)) || seen.has(id)) {
      while (seen.has(prefix + n)) n++;
      id = prefix + n;
    }
    seen.add(id);
    it.id = id;
  });
  return seen;
}

CC.KINDS = ["criminal", "civil", "constitutional", "ethical"];

CC.normalizeCase = function (raw, cfg) {
  raw = raw && typeof raw === "object" ? raw : {};
  cfg = cfg || {};
  const kind = CC.KINDS.includes(raw.kind) ? raw.kind : CC.KINDS.includes(cfg.kind) ? cfg.kind : "criminal";
  const jurisdiction = CC.JURISDICTIONS[cfg.jurisdiction] ? cfg.jurisdiction : CC.JURISDICTIONS[raw.jurisdiction] ? raw.jurisdiction : "unspecified";
  const c = {
    version: 2,
    id: "case-" + (cfg.seed >>> 0).toString(36),
    seed: cfg.seed >>> 0,
    kind,
    jurisdiction,
    title: str(raw.title, 90) || "Untitled matter",
    summary: txt(raw.summary, 900),
    parties: { pros: str(raw.parties && raw.parties.pros, 80) || CC.sidesFor(kind, jurisdiction).pros, def: str(raw.parties && raw.parties.def, 80) || "The respondent" },
    edgeCase: txt(raw.edgeCase, 400),
    lawNotes: arr(raw.lawNotes).slice(0, 8).map((n) => ({ text: txt(typeof n === "string" ? n : n.text, 500), verified: false })).filter((n) => n.text),
    config: Object.assign({}, cfg),
  };
  c.charges = arr(raw.charges).slice(0, 3).map((ch) => ({ id: ch.id, name: str(ch.name, 90), elements: arr(ch.elements).slice(0, 6).map((e) => ({ id: e.id, text: str(typeof e === "string" ? e : e.text, 300) })).filter((e) => e.text) })).filter((ch) => ch.name && ch.elements.length);
  if (!c.charges.length) c.charges = [{ id: "C1", name: "The claim", elements: [{ id: "C1-E1", text: "The conduct alleged occurred." }] }];
  uniqueIds(c.charges, "C", /^C\d+$/);
  c.charges.forEach((ch) => {
    ch.elements.forEach((e, i) => { e.id = `${ch.id}-E${i + 1}`; });
  });
  c.defenses = arr(raw.defenses).slice(0, 4).map((d) => ({ id: d.id, name: str(d.name, 90), appliesTo: arr(d.appliesTo).map((x) => str(x, 8).toUpperCase()), elements: arr(d.elements).slice(0, 4).map((e) => ({ text: str(typeof e === "string" ? e : e.text, 300) })).filter((e) => e.text), burdenNote: str(d.burdenNote, 300) })).filter((d) => d.name);
  uniqueIds(c.defenses, "DEF", /^DEF\d+$/);
  const chargeIds = new Set(c.charges.map((ch) => ch.id));
  c.defenses.forEach((d) => {
    d.appliesTo = d.appliesTo.filter((x) => chargeIds.has(x));
    if (!d.appliesTo.length) d.appliesTo = [...chargeIds];
    d.elements.forEach((e, i) => { e.id = `${d.id}-E${i + 1}`; });
  });
  c.agreedFacts = arr(raw.agreedFacts).slice(0, 12).map((f) => ({ id: f.id, text: str(typeof f === "string" ? f : f.text, 400) })).filter((f) => f.text);
  uniqueIds(c.agreedFacts, "AF", /^AF\d+$/);
  c.disputedFacts = arr(raw.disputedFacts).slice(0, 10).map((f) => ({ id: f.id, text: str(typeof f === "string" ? f : f.text, 400), prosTheory: str(f.prosecutionTheory || f.prosTheory, 400), defTheory: str(f.defenseTheory || f.defTheory, 400) })).filter((f) => f.text);
  uniqueIds(c.disputedFacts, "DF", /^DF\d+$/);
  c.questions = arr(raw.questions).slice(0, 8).map((q) => ({ id: q.id, text: str(typeof q === "string" ? q : q.text, 300) })).filter((q) => q.text);
  uniqueIds(c.questions, "Q", /^Q\d+$/);
  c.theories = arr(raw.theories).slice(0, 6).map((t) => ({ id: t.id, side: ["pros", "prosecution", "def", "defense", "neutral"].includes(t.side) ? (t.side.startsWith("pros") ? "pros" : t.side.startsWith("def") ? "def" : "neutral") : "neutral", text: str(t.text, 400) })).filter((t) => t.text);
  uniqueIds(c.theories, "T", /^TH\d+$/);
  c.theories.forEach((t, i) => { t.id = "TH" + (i + 1); });
  const dfIds = new Set(c.disputedFacts.map((f) => f.id));
  c.witnesses = arr(raw.witnesses).slice(0, 6).map((w) => ({
    id: w.id, name: str(w.name, 60), calledBy: /^def/i.test(w.calledBy || "") ? "def" : "pros", role: str(w.role, 60),
    summary: str(w.summary, 300), priorStatement: txt(w.priorStatement, 900), brief: txt(w.knows || w.brief, 1500),
    limitations: str(w.limitations, 400), relatesTo: arr(w.relatesTo).map((x) => str(x, 8).toUpperCase()).filter((x) => dfIds.has(x)),
  })).filter((w) => w.name);
  uniqueIds(c.witnesses, "W", /^W\d+$/);
  c.exhibits = arr(raw.exhibits).slice(0, 10).map((x) => CC.normalizeExhibit(x, x.offeredBy));
  const used = new Set();
  const counters = { P: 0, D: 0, C: 0, U: 0 };
  c.exhibits.forEach((x) => {
    const p = x.offeredBy === "def" ? "D" : x.offeredBy === "court" ? "C" : "P";
    let id = str(x.id, 8).toUpperCase();
    if (!/^[PDCU]-\d+$/.test(id) || used.has(id)) { do { counters[p]++; id = `${p}-${counters[p]}`; } while (used.has(id)); }
    used.add(id); x.id = id;
  });
  const exIds = new Set(c.exhibits.map((x) => x.id));
  c.exhibits.forEach((x) => {
    x.relatesTo = x.relatesTo.filter((r) => dfIds.has(r));
    x.supports = x.supports.filter((r) => exIds.has(r) && r !== x.id);
    x.contradicts = x.contradicts.filter((r) => exIds.has(r) && r !== x.id);
  });
  c.testimony = [];
  c.objections = [];
  c.motions = [];
  c.statements = [];
  c.contradictions = [];
  c.userAuthorities = [];
  const ids = CC.recordIds(c);
  arr(raw.seededContradictions || raw.contradictions).slice(0, 8).forEach((x) => {
    const a = str(x.a, 10).toUpperCase(), b = str(x.b, 10).toUpperCase();
    if (ids.has(a) && ids.has(b) && a !== b) CC.addContradiction(c, { a, b, description: str(x.description, 400), severity: x.severity === "minor" ? "minor" : "material", intentional: true, source: "case file" });
  });
  c.stage = 0;
  c.progress = {};
  c.jurors = CC.defaultJurors(c.seed);
  c.analysis = null;
  c.report = null;
  c.juryRuns = [];
  return c;
};

CC.normalizeExhibit = function (x, offeredBy) {
  x = x && typeof x === "object" ? x : {};
  const by = /^def/i.test(offeredBy || x.offeredBy || "") ? "def" : /court/i.test(offeredBy || x.offeredBy || "") ? "court" : /user/i.test(offeredBy || "") ? "user" : "pros";
  const issue = str(x.admissibilityIssue, 160);
  return {
    id: str(x.id, 8).toUpperCase(),
    title: str(x.title, 90) || "Untitled exhibit",
    description: txt(x.description, 700),
    source: str(x.source, 240) || "Source not stated",
    offeredBy: by,
    relatesTo: arr(x.relatesTo).map((r) => str(r, 8).toUpperCase()),
    reliability: str(x.reliability, 400) || "No reliability limitations were identified when it was filed.",
    supports: arr(x.supports).map((r) => str(r, 8).toUpperCase()),
    contradicts: arr(x.contradicts).map((r) => str(r, 8).toUpperCase()),
    admissibilityIssue: /^(none|n\/a|no)\.?$/i.test(issue) ? "" : issue,
    status: "pending",
    ruling: "",
  };
};

/* Every id a party, witness or juror may cite. */
CC.recordIds = function (c) {
  const s = new Set();
  [c.agreedFacts, c.disputedFacts, c.questions, c.witnesses, c.exhibits, c.testimony, c.contradictions, c.defenses, c.theories, c.statements].forEach((list) => arr(list).forEach((x) => s.add(x.id)));
  arr(c.charges).forEach((ch) => { s.add(ch.id); ch.elements.forEach((e) => s.add(e.id)); });
  arr(c.defenses).forEach((d) => d.elements.forEach((e) => s.add(e.id)));
  arr(c.witnesses).forEach((w) => s.add(w.id + "-PS"));
  return s;
};

CC.validateIds = function (list, ids) {
  const kept = [], dropped = [];
  arr(list).forEach((x) => { const id = str(x, 16).toUpperCase(); (ids.has(id) ? kept : dropped).push(id); });
  return { kept: [...new Set(kept)], dropped };
};

CC.nextId = function (prefix, list) {
  let n = 0;
  arr(list).forEach((x) => { const m = String(x.id).match(/(\d+)$/); if (m) n = Math.max(n, +m[1]); });
  return prefix + (n + 1);
};

CC.addContradiction = function (c, x) {
  const key = [x.a, x.b].sort().join("|");
  const existing = c.contradictions.find((k) => [k.a, k.b].sort().join("|") === key);
  if (existing) return existing;
  const item = { id: CC.nextId("X", c.contradictions), a: x.a, b: x.b, description: str(x.description, 400), severity: x.severity === "minor" ? "minor" : "material", intentional: !!x.intentional, source: x.source || "clerk" };
  c.contradictions.push(item);
  return item;
};

CC.addTestimony = function (c, t) {
  const item = {
    id: CC.nextId("T", c.testimony), witnessId: t.witnessId, stage: t.stage, askedBy: t.askedBy,
    question: txt(t.question, 600), answer: txt(t.answer, 1500), claims: [], struck: false, objection: t.objection || null,
  };
  c.testimony.push(item);
  return item;
};

CC.addStatement = function (c, s) {
  const item = { id: CC.nextId("S", c.statements), side: s.side, type: s.type, by: s.by || "ai", text: txt(s.text, 4000) };
  c.statements.push(item);
  return item;
};

CC.findItem = function (c, id) {
  id = String(id || "").toUpperCase();
  if (/-PS$/.test(id)) { const w = c.witnesses.find((x) => x.id + "-PS" === id); return w ? { type: "prior statement", label: `${w.name}'s prior statement`, item: w } : null; }
  const lists = [["agreed fact", c.agreedFacts], ["disputed fact", c.disputedFacts], ["exhibit", c.exhibits], ["testimony", c.testimony], ["witness", c.witnesses], ["contradiction", c.contradictions], ["statement", c.statements], ["defense", c.defenses], ["question", c.questions], ["theory", c.theories]];
  for (const [type, list] of lists) { const it = arr(list).find((x) => x.id === id); if (it) return { type, item: it, label: it.title || it.name || it.text || it.question || it.description || id }; }
  for (const ch of arr(c.charges)) { if (ch.id === id) return { type: "charge", item: ch, label: ch.name }; const e = ch.elements.find((x) => x.id === id); if (e) return { type: "element", item: e, label: e.text }; }
  return null;
};

/* ---------- jury instructions (deterministic, built from the record) ---------- */
CC.juryInstructions = function (c) {
  const j = CC.jurisdiction(c.jurisdiction);
  const rule = CC.decisionRule(c.jurisdiction, c.kind);
  const labels = CC.labelsFor(c.kind, j.factfinder);
  const sides = CC.sidesFor(c.kind, c.jurisdiction);
  const lines = [];
  lines.push(`Jurisdiction: ${j.name}.`);
  lines.push(`Standard of proof: ${CC.standardFor(c.jurisdiction, c.kind)}.`);
  lines.push(`Burden: ${j.burden}`);
  c.charges.forEach((ch) => {
    lines.push(`${ch.id} — ${ch.name}. To return ${labels.yes} on this count you must find every element proven to the standard:`);
    ch.elements.forEach((e) => lines.push(`  ${e.id}: ${e.text}`));
    lines.push(`  If any element is not proven to that standard, your vote on ${ch.id} must be ${labels.no}.`);
  });
  c.defenses.forEach((d) => {
    lines.push(`${d.id} — ${d.name} (applies to ${d.appliesTo.join(", ")}): ${d.elements.map((e) => e.text).join(" ")}`);
    lines.push(`  Burden on this defense: ${d.burdenNote || j.defenseBurden}`);
  });
  lines.push("Evidence: only admitted exhibits and testimony that was not struck are evidence. Opening statements, closing arguments, questions and objections are not evidence.");
  lines.push(`Testimony and prior statements are claims by the person making them. They are not established facts until you find them proven. Agreed facts are established.`);
  lines.push("Exhibits admitted for a limited purpose may be used only for that purpose. Struck testimony and excluded exhibits must be disregarded.");
  lines.push(`Do not use any legal rule that is not stated here or in the case file's law notes. Those law notes are descriptions written for this simulation and have not been verified.`);
  lines.push(`Decision rule: ${rule.text}${rule.assumption ? " (" + rule.assumption + ")" : ""}`);
  lines.push(`Legal guilt or liability is a separate question from moral blame and from punishment or remedy. You decide only whether ${sides.pros.toLowerCase()} has proven each count.`);
  return lines.join("\n");
};

/* ---------- record digest for prompts ---------- */
CC.recordDigest = function (c, opts) {
  opts = opts || {};
  const j = CC.jurisdiction(c.jurisdiction);
  const sides = CC.sidesFor(c.kind, c.jurisdiction);
  const out = [];
  out.push(`CASE: ${c.title} (${c.kind}; ${j.name})`);
  out.push(`${sides.pros}: ${c.parties.pros}. ${sides.def}: ${c.parties.def}.`);
  if (c.summary) out.push(`Summary: ${c.summary}`);
  out.push(`Standard of proof: ${CC.standardFor(c.jurisdiction, c.kind)}. Burden: ${j.burden}`);
  out.push("COUNTS AND ELEMENTS:");
  c.charges.forEach((ch) => { out.push(`${ch.id} ${ch.name}`); ch.elements.forEach((e) => out.push(`  ${e.id}: ${e.text}`)); });
  if (c.defenses.length) { out.push("DEFENSES:"); c.defenses.forEach((d) => out.push(`${d.id} ${d.name} [applies to ${d.appliesTo.join(", ")}]: ${d.elements.map((e) => e.text).join(" ")}${d.burdenNote ? " Burden: " + d.burdenNote : ""}`)); }
  if (c.lawNotes.length) { out.push("LAW NOTES (simulation descriptions, NOT verified sources):"); c.lawNotes.forEach((n) => out.push(`- ${n.text}`)); }
  if (c.userAuthorities.length) { out.push("AUTHORITIES SUPPLIED BY THE USER (not verified by the app):"); c.userAuthorities.forEach((a) => out.push(`- ${a.label}: ${a.text}`)); }
  out.push("AGREED FACTS (established):");
  c.agreedFacts.forEach((f) => out.push(`${f.id}: ${f.text}`));
  out.push("DISPUTED FACTS:");
  c.disputedFacts.forEach((f) => out.push(`${f.id}: ${f.text}${f.prosTheory ? ` | ${sides.pros} says: ${f.prosTheory}` : ""}${f.defTheory ? ` | ${sides.def} says: ${f.defTheory}` : ""}`));
  if (c.questions.length) { out.push("QUESTIONS FOR THE COURT:"); c.questions.forEach((q) => out.push(`${q.id}: ${q.text}`)); }
  const admitted = c.exhibits.filter((x) => x.status === "admitted" || x.status === "limited" || (opts.includePending && x.status === "pending"));
  out.push("EXHIBITS" + (opts.includePending ? " (status shown)" : " IN EVIDENCE") + ":");
  admitted.forEach((x) => out.push(`${x.id} [${x.status}${x.status === "limited" && x.ruling ? ": " + x.ruling : ""}] ${x.title}: ${x.description} Source: ${x.source}. Reliability limits: ${x.reliability}${x.relatesTo.length ? ` Relates to ${x.relatesTo.join(", ")}.` : ""}`));
  const excluded = c.exhibits.filter((x) => x.status === "excluded");
  if (excluded.length) out.push(`EXCLUDED (must be disregarded): ${excluded.map((x) => x.id).join(", ")}`);
  if (opts.witnessStatements) {
    out.push("WITNESSES AND PRIOR STATEMENTS (allegations, not facts):");
    c.witnesses.forEach((w) => out.push(`${w.id} ${w.name} (${w.role}, called by ${sides[w.calledBy]}): ${w.summary}${w.priorStatement ? ` Prior statement [${w.id}-PS]: "${w.priorStatement}"` : ""}`));
  } else {
    out.push("WITNESSES: " + c.witnesses.map((w) => `${w.id} ${w.name} (${w.role}, ${sides[w.calledBy]})`).join("; "));
  }
  const live = c.testimony.filter((t) => !t.struck);
  if (live.length) {
    out.push("TESTIMONY (each answer is a claim by the witness, not an established fact):");
    live.slice(-(opts.maxTestimony || 60)).forEach((t) => out.push(`${t.id} ${t.witnessId} ${t.stage} — Q: ${t.question} A: ${t.answer}`));
  }
  const struck = c.testimony.filter((t) => t.struck);
  if (struck.length) out.push(`STRUCK TESTIMONY (disregard): ${struck.map((t) => t.id).join(", ")}`);
  if (c.contradictions.length) { out.push("CONTRADICTIONS LOGGED:"); c.contradictions.forEach((x) => out.push(`${x.id} [${x.severity}${x.intentional ? ", from case file" : ""}] ${x.a} vs ${x.b}: ${x.description}`)); }
  const rulings = c.objections.filter((o) => o.ruling);
  if (rulings.length && opts.rulings !== false) { out.push("RULINGS:"); rulings.slice(-12).forEach((o) => out.push(`${o.id} ${o.ground} by ${o.by} on ${o.target}: ${o.ruling.toUpperCase()} — ${o.reason}`)); }
  if (opts.statements) {
    out.push("STATEMENTS AND ARGUMENTS (advocacy, not evidence):");
    c.statements.forEach((s) => out.push(`${s.id} ${sides[s.side]} ${s.type}: ${s.text.slice(0, opts.statementChars || 900)}`));
  }
  return out.join("\n");
};

/* ---------- authorities: only what can be traced ---------- */
CC.filterAuthorities = function (list, c) {
  const known = CC.jurisdiction(c.jurisdiction).references.map((r) => r.label.toLowerCase());
  const user = c.userAuthorities.map((a) => a.label.toLowerCase());
  const kept = [], removed = [];
  arr(list).forEach((a) => {
    const label = str(typeof a === "string" ? a : a.label, 200);
    if (!label) return;
    const l = label.toLowerCase();
    const k = known.find((x) => x.includes(l) || l.includes(x.split(" — ")[0]));
    const u = user.find((x) => x === l || l.includes(x) || x.includes(l));
    if (k) kept.push({ label, verified: false, origin: "Built-in jurisdiction summary", note: CC.UNVERIFIED_NOTE });
    else if (u) kept.push({ label, verified: false, origin: "Supplied by you", note: "Supplied by the user; the app cannot verify it." });
    else removed.push(label);
  });
  return { kept, removed };
};

/* ---------- juror consistency checks ---------- */
CC.checkJuror = function (c, analysis) {
  const warnings = [];
  const findings = arr(analysis && analysis.elementFindings);
  const defenseFindings = arr(analysis && analysis.defenseFindings);
  c.charges.forEach((ch) => {
    const v = (arr(analysis && analysis.votes).find((x) => x.charge === ch.id) || {}).vote;
    if (!v) { warnings.push(`No vote recorded on ${ch.id}.`); return; }
    const els = ch.elements.map((e) => (findings.find((f) => f.element === e.id) || {}).finding || "uncertain");
    const allProven = els.every((f) => f === "proven");
    const defense = defenseFindings.some((d) => d.finding === "established" && (CC.findItem(c, d.defense) || {}).item && CC.findItem(c, d.defense).item.appliesTo.includes(ch.id));
    if (v === "yes" && !allProven) warnings.push(`Voted yes on ${ch.id} without finding every element proven.`);
    if (v === "yes" && defense) warnings.push(`Voted yes on ${ch.id} while finding a defense established.`);
    if (v === "no" && allProven && !defense) warnings.push(`Voted no on ${ch.id} although every element was found proven and no defense established; this may reflect a moral rather than legal judgment.`);
  });
  return warnings;
};

/* Normalize a juror's JSON analysis against the record. */
CC.normalizeJuror = function (c, raw) {
  raw = raw && typeof raw === "object" ? raw : {};
  const ids = CC.recordIds(c);
  const dropped = [];
  const elementIds = new Set(); c.charges.forEach((ch) => ch.elements.forEach((e) => elementIds.add(e.id)));
  const findings = arr(raw.elementFindings).map((f) => {
    const basis = CC.validateIds(f.basis, ids); dropped.push(...basis.dropped);
    const fd = String(f.finding || "").toLowerCase();
    return { element: str(f.element, 12).toUpperCase(), finding: /not/.test(fd) ? "not proven" : /proven|yes|established/.test(fd) ? "proven" : "uncertain", basis: basis.kept, reason: str(f.reason, 400) };
  }).filter((f) => elementIds.has(f.element));
  const defIds = new Set(c.defenses.map((d) => d.id));
  const defenseFindings = arr(raw.defenseFindings).map((d) => {
    const fd = String(d.finding || "").toLowerCase();
    return { defense: str(d.defense, 10).toUpperCase(), finding: /not/.test(fd) ? "not established" : /establish|yes|succeed/.test(fd) ? "established" : "uncertain", reason: str(d.reason, 400) };
  }).filter((d) => defIds.has(d.defense));
  const votes = c.charges.map((ch) => {
    const v = arr(raw.votes).find((x) => str(x.charge, 8).toUpperCase() === ch.id);
    const s = String(v && v.vote || "").toLowerCase();
    return { charge: ch.id, vote: /^(no|not)/.test(s) || /not guilty|not liable|no violation|reject/.test(s) ? "no" : /^(yes|guilty|liable|violation|upheld)/.test(s) ? "yes" : null };
  });
  const out = {
    issues: arr(raw.issues).slice(0, 6).map((x) => str(x, 240)).filter(Boolean),
    elementFindings: findings,
    defenseFindings,
    votes,
    confidence: Math.max(1, Math.min(5, Math.round(Number(raw.confidence)) || 3)),
    keyReasons: arr(raw.keyReasons).slice(0, 4).map((x) => str(x, 400)).filter(Boolean),
    doubts: arr(raw.doubts).slice(0, 4).map((x) => str(x, 300)).filter(Boolean),
    wouldChangeIf: str(raw.wouldChangeIf, 300),
    strongestCounter: str(raw.strongestCounter, 400),
    response: str(raw.response, 500),
    revised: !!raw.revised,
    revisionReason: str(raw.revisionReason, 400),
    challenges: arr(raw.challenges).slice(0, 3).map((x) => ({ to: str(x.to, 6).toUpperCase(), point: str(x.point, 300) })).filter((x) => x.point),
    droppedCitations: [...new Set(dropped)],
  };
  out.warnings = CC.checkJuror(c, out);
  return out;
};

/* Tally final votes per charge under the decision rule. */
CC.tallyVerdict = function (c, stage) {
  const j = CC.jurisdiction(c.jurisdiction);
  const rule = CC.decisionRule(c.jurisdiction, c.kind);
  const labels = CC.labelsFor(c.kind, j.factfinder);
  return c.charges.map((ch) => {
    const votes = c.jurors.map((jr) => { const a = jr[stage || "final"] || jr.provisional; const v = a && a.votes.find((x) => x.charge === ch.id); return v ? v.vote : null; });
    const r = CC.applyRule(rule, votes);
    return Object.assign({ charge: ch.id, name: ch.name, label: labels[r.result], rule: rule.type, ruleText: rule.text, assumption: rule.assumption }, r);
  });
};

/* What other decision rules would have produced, for the counterfactual section. */
CC.alternativeRules = function (c) {
  const rules = [{ name: "Unanimous", rule: { type: "unanimous" } }, { name: "At least 10 of 12", rule: { type: "supermajority", min: 10 } }, { name: "Simple majority", rule: { type: "majority" } }];
  const labels = CC.labelsFor(c.kind, CC.jurisdiction(c.jurisdiction).factfinder);
  return c.charges.map((ch) => {
    const votes = c.jurors.map((jr) => { const a = jr.final || jr.provisional; const v = a && a.votes.find((x) => x.charge === ch.id); return v ? v.vote : null; });
    return { charge: ch.id, results: rules.map((r) => ({ name: r.name, label: labels[CC.applyRule(r.rule, votes).result] })) };
  });
};

CC.STAGES = [
  { key: "filing", name: "Filing" },
  { key: "openings", name: "Openings" },
  { key: "evidence", name: "Evidence" },
  { key: "direct", name: "Direct" },
  { key: "cross", name: "Cross" },
  { key: "closings", name: "Closings" },
  { key: "jury", name: "Deliberation" },
  { key: "verdict", name: "Verdict" },
];

CC.OBJECTION_GROUNDS = ["Hearsay", "Leading", "Relevance", "Speculation", "Argumentative", "Asked and answered", "Lack of foundation", "Beyond the scope", "Compound question", "Assumes facts not in evidence", "Unfair prejudice", "Privilege"];

CC.EDGE_CASES = [
  { id: "none", name: "None" },
  { id: "random", name: "Surprise me" },
  { id: "eyewitness", name: "Eyewitness identification in poor conditions" },
  { id: "self-defense", name: "Self-defense with an honest but possibly unreasonable belief" },
  { id: "claim-of-right", name: "Taking property under a claim of right" },
  { id: "circumstantial", name: "Purely circumstantial evidence" },
  { id: "hearsay", name: "Key witness unavailable; case rests on hearsay" },
  { id: "experts", name: "Competing expert witnesses" },
  { id: "chain-of-custody", name: "Broken chain of custody" },
  { id: "recantation", name: "A witness recants an earlier statement" },
  { id: "necessity", name: "Necessity or duress" },
  { id: "capacity", name: "Disputed mental capacity or intent" },
  { id: "search", name: "Evidence from a disputed search" },
  { id: "corporate", name: "Corporate versus individual responsibility" },
  { id: "contract-ambiguity", name: "Ambiguous contract term" },
  { id: "moral-legal-gap", name: "Legally guilty but morally sympathetic" },
  { id: "duty-conflict", name: "Conflicting ethical duties" },
];

if (typeof module !== "undefined" && module.exports) module.exports = CC;
})(typeof window !== "undefined" ? window : globalThis);
