// tooc web — the same Firebase data as the iOS app (fftooc), drawn to look like it.
//
// Message kinds are stored as the JSON Swift's Codable makes, e.g. {"text":{"_0":"hi"}}, and dates inside them as
// seconds since 2001-01-01, so both apps read each other's messages.

import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js";
import {
  getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, signOut,
  updatePassword, reauthenticateWithCredential, EmailAuthProvider, deleteUser,
} from "https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js";
import {
  getFirestore, doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, onSnapshot, query, where, orderBy,
  limitToLast, limit, Timestamp, arrayUnion, arrayRemove, deleteField, writeBatch, FieldPath,
} from "https://www.gstatic.com/firebasejs/11.0.2/firebase-firestore.js";
import { getStorage, ref as storageRef, uploadBytes, getDownloadURL } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-storage.js";
import qrcode from "https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/+esm";
import { firebaseConfig } from "./config.js";

const $app = document.getElementById("app");
const $layer = document.getElementById("layer");
const REF = 978307200; // 2001-01-01 in Unix seconds
const EMOJIS = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🎉", "🔥"];
const THEMES = [["standard", "標準"], ["sky", "空"], ["sakura", "さくら"], ["mint", "ミント"], ["sand", "すな"], ["night", "夜"]];
const SIZES = [["small", "小", 15], ["standard", "標準", 17], ["large", "大", 20], ["larger", "特大", 23]];
const REPLIES_OK = /^[a-z0-9._]{4,20}$/;

// ---------------------------------------------------------------- small helpers

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const uuid = () => crypto.randomUUID().toUpperCase();
const email = (id) => `${id}@fftooc.app`;
const now = () => new Date();
const toRef = (date) => date.getTime() / 1000 - REF;
const fromRef = (seconds) => new Date((seconds + REF) * 1000);
const pad = (n) => String(n).padStart(2, "0");
const clock = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const sameDay = (a, b) => a.toDateString() === b.toDateString();
const WEEK = ["日", "月", "火", "水", "木", "金", "土"];
function listLabel(d) {
  const today = now();
  if (sameDay(d, today)) return clock(d);
  const y = new Date(today); y.setDate(y.getDate() - 1);
  if (sameDay(d, y)) return "昨日";
  return d.getFullYear() === today.getFullYear() ? `${d.getMonth() + 1}/${d.getDate()}` : `${d.getFullYear()}/${pad(d.getMonth() + 1)}/${pad(d.getDate())}`;
}
function dayLabel(d) {
  const today = now();
  if (sameDay(d, today)) return "今日";
  const y = new Date(today); y.setDate(y.getDate() - 1);
  if (sameDay(d, y)) return "昨日";
  const md = `${d.getMonth() + 1}月${d.getDate()}日(${WEEK[d.getDay()]})`;
  return d.getFullYear() === today.getFullYear() ? md : `${d.getFullYear()}年${md}`;
}
const candidate = (d) => `${d.getMonth() + 1}/${d.getDate()}(${WEEK[d.getDay()]}) ${clock(d)}`;
const hueFor = (text) => { let h = 0; for (const c of text) h = (h * 31 + c.codePointAt(0)) % 997; return h / 997; };
const bytes = (n) => n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(0)} KB` : `${(n / 1048576).toFixed(1)} MB`;
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

// A few SF-Symbol-like icons.
const ICONS = {
  back: '<path d="M15 4l-8 8 8 8"/>', plus: '<path d="M12 5v14M5 12h14"/>', search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
  more: '<circle cx="5" cy="12" r="1.6" class="dot"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>',
  sort: '<path d="M7 4v16M4 7l3-3 3 3M17 20V4M14 17l3 3 3-3"/>', bell: '<path d="M6 16V11a6 6 0 1112 0v5l2 2H4z"/><path d="M10 20a2 2 0 004 0"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>', check: '<path d="M5 12l5 5L20 7"/>', message: '<path d="M4 5h16v11H9l-5 4z"/>',
  people: '<circle cx="9" cy="8" r="3.2"/><path d="M3 19c0-3.3 2.7-5 6-5s6 1.7 6 5"/><circle cx="17" cy="9" r="2.5"/><path d="M16 14c2.8 0 5 1.4 5 4"/>',
  face: '<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5c1.8 2 5.2 2 7 0"/><path d="M9 9.5h.01M15 9.5h.01"/>',
  photo: '<rect x="3" y="5" width="18" height="14" rx="3"/><circle cx="9" cy="10" r="1.8"/><path d="M3 17l5-5 4 4 3-3 6 6"/>',
  camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>', doc: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4"/>',
  pin: '<path d="M12 21v-6M8 3h8l-1 6 3 3H6l3-3z"/>', clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  qr: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><path d="M14 14h3v3h-3zM20 14v.01M14 20h.01M17 17h3v3"/>',
  at: '<circle cx="12" cy="12" r="4"/><path d="M16 12v1.5a2.5 2.5 0 005 0V12a9 9 0 10-3.5 7.1"/>', pencil: '<path d="M4 20h4L20 8l-4-4L4 16z"/>',
  send: '<path d="M12 19V5M6 11l6-6 6 6"/>', chevron: '<path d="M9 5l7 7-7 7"/>', note: '<path d="M6 3h12v18H6z"/><path d="M9 8h6M9 12h6M9 16h4"/>',
  mappin: '<path d="M12 21s-7-6.2-7-11a7 7 0 0114 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>', chart: '<path d="M5 20V10M12 20V4M19 20v-7"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18M8 3v4M16 3v4"/>', ladder: '<path d="M6 3v18M18 3v18M6 8h12M6 16h12"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>', reply: '<path d="M10 7L4 12l6 5"/><path d="M4 12h10a6 6 0 016 6"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V4H4v12h4"/>', undo: '<path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 010 10h-3"/>',
  eyeoff: '<path d="M3 3l18 18"/><path d="M10.6 6.1A10 10 0 0121 12a12 12 0 01-3 3.6M6.6 6.6A12 12 0 003 12s3.5 6 9 6a9 9 0 004.4-1.1"/>',
  star: '<path d="M12 3l2.8 5.8 6.2.9-4.5 4.4 1.1 6.2L12 17.4l-5.6 2.9 1.1-6.2L3 9.7l6.2-.9z"/>', block: '<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>',
  share: '<path d="M12 3v13M7 8l5-5 5 5"/><path d="M5 12v8h14v-8"/>', download: '<path d="M12 4v12M7 11l5 5 5-5"/><path d="M5 20h14"/>',
  muted: '<path d="M4 9h4l5-4v14l-5-4H4z"/><path d="M17 9l4 6M21 9l-4 6"/>', user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>',
  lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 018 0v4"/>', scan: '<path d="M4 8V4h4M16 4h4v4M20 16v4h-4M8 20H4v-4M4 12h16"/>',
};
const icon = (name, cls = "") => `<svg class="svg ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ""}</svg>`;

function toast(text) {
  const el = document.createElement("div");
  el.className = "toast glass";
  el.textContent = text;
  document.body.append(el);
  setTimeout(() => el.remove(), 2200);
}

// ---------------------------------------------------------------- Codable kinds

function decodeKind(json) {
  let k;
  try { k = JSON.parse(json); } catch { return null; }
  const type = Object.keys(k)[0];
  const v = k[type] || {};
  switch (type) {
    case "text": return { type, text: v._0 ?? "" };
    case "photo": return { type, file: v._0 ?? null };
    case "remotePhoto": return { type, url: v._0 };
    case "file": return { type, name: v.name, file: v.file, size: v.size };
    case "remoteFile": return { type, name: v.name, url: v.url, size: v.size };
    case "location": return { type, latitude: v.latitude, longitude: v.longitude, title: v.title };
    case "poll": { const p = v._0; return { type, question: p.question, options: p.options, multiple: p.multiple, deadline: p.deadline != null ? fromRef(p.deadline) : null }; }
    case "datePoll": { const p = v._0; return { type, title: p.title, dates: p.dates.map(fromRef), deadline: p.deadline != null ? fromRef(p.deadline) : null }; }
    case "amida": { const a = v._0; return { type, title: a.title, entrants: a.entrants, prizes: a.prizes, rungs: a.rungs, deadline: a.deadline != null ? fromRef(a.deadline) : null }; }
    case "unsent": return { type };
    default: return null;
  }
}

function encodeKind(kind) {
  const withDeadline = (o, d) => (d ? { ...o, deadline: toRef(d) } : o);
  switch (kind.type) {
    case "text": return JSON.stringify({ text: { _0: kind.text } });
    case "remotePhoto": return JSON.stringify({ remotePhoto: { _0: kind.url } });
    case "remoteFile": return JSON.stringify({ remoteFile: { name: kind.name, url: kind.url, size: kind.size } });
    case "location": return JSON.stringify({ location: { latitude: kind.latitude, longitude: kind.longitude, title: kind.title } });
    case "poll": return JSON.stringify({ poll: { _0: withDeadline({ question: kind.question, options: kind.options, multiple: kind.multiple, votes: {} }, kind.deadline) } });
    case "datePoll": return JSON.stringify({ datePoll: { _0: withDeadline({ title: kind.title, dates: kind.dates.map(toRef), answers: {} }, kind.deadline) } });
    case "amida": return JSON.stringify({ amida: { _0: withDeadline({ title: kind.title, entrants: kind.entrants, prizes: kind.prizes, rungs: kind.rungs, revealed: false }, kind.deadline) } });
    case "unsent": return JSON.stringify({ unsent: {} });
    default: return "{}";
  }
}

function preview(kind) {
  switch (kind?.type) {
    case "text": return kind.text;
    case "photo": case "remotePhoto": return "写真";
    case "file": case "remoteFile": return `ファイル：${kind.name}`;
    case "location": return `位置情報：${kind.title}`;
    case "poll": return `投票：${kind.question}`;
    case "datePoll": return `日程調整：${kind.title}`;
    case "amida": return `あみだくじ：${kind.title}`;
    case "unsent": return "送信が取り消されました";
    default: return "";
  }
}

// ---------------------------------------------------------------- accounts (one Firebase app per account)

const configured = Boolean(firebaseConfig.apiKey && firebaseConfig.appId);
const apps = {};
function appFor(id) {
  if (!apps[id]) {
    const app = initializeApp(firebaseConfig, `tooc-${id}`);
    apps[id] = { auth: getAuth(app), db: getFirestore(app), storage: getStorage(app) };
  }
  return apps[id];
}
const saved = {
  get list() { try { return JSON.parse(localStorage.getItem("tooc.accounts") || "[]"); } catch { return []; } },
  set list(v) { localStorage.setItem("tooc.accounts", JSON.stringify(v)); },
  get current() { return localStorage.getItem("tooc.current"); },
  set current(v) { v ? localStorage.setItem("tooc.current", v) : localStorage.removeItem("tooc.current"); },
  get previous() { return localStorage.getItem("tooc.previous"); },
  set previous(v) { v ? localStorage.setItem("tooc.previous", v) : localStorage.removeItem("tooc.previous"); },
  remember(user) {
    const list = this.list.filter((a) => a.id !== user.id);
    list.push({ id: user.id, name: user.name, hue: user.hue, iconURL: user.iconURL || null });
    this.list = list;
  },
  forget(id) { this.list = this.list.filter((a) => a.id !== id); if (this.previous === id) this.previous = null; },
};

// ---------------------------------------------------------------- state

const S = {
  account: null, fb: null, uid: null, me: null,
  profiles: {}, friendIDs: {}, requestIDs: {}, rooms: {}, messages: {}, readBy: {}, typing: {}, pending: {},
  listeners: {}, loaded: new Set(),
  local: null,
  tab: "talk", filter: "all", view: null, sheet: null, openRoom: null,
  draft: "", replyTo: null, editing: null, attachments: [],
  banner: null,
};

function loadLocal(id) {
  let l = {};
  try { l = JSON.parse(localStorage.getItem(`tooc.local.${id}`) || "{}"); } catch {}
  return {
    rooms: l.rooms || {}, friends: l.friends || {}, notices: l.notices || [], scheduled: l.scheduled || {}, revealed: l.revealed || [],
    settings: Object.assign({ notifications: true, showContent: true, textSize: "standard", theme: "standard", returnSends: false, favoriteReactions: ["👍", "❤️", "😂", "😮", "🙏"] }, l.settings || {}),
    talkSort: l.talkSort || "conversation", friendSort: l.friendSort || "added", favoritesFirst: !!l.favoritesFirst, unreadFirst: !!l.unreadFirst,
  };
}
let saveTimer;
function saveLocal() {
  if (!S.account) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => localStorage.setItem(`tooc.local.${S.account}`, JSON.stringify(S.local)), 300);
}
const roomPrefs = (id) => (S.local.rooms[id] ||= { pinned: false, muted: false, hidden: false, draft: "", lastRead: 0, clearedAt: 0, deleted: [] });
const friendPrefs = (id) => (S.local.friends[id] ||= { favorite: false, hidden: false, blocked: false, nickname: null });

function applyTheme() {
  const s = S.local?.settings;
  document.documentElement.dataset.theme = s?.theme || "standard";
  const size = SIZES.find((x) => x[0] === s?.textSize)?.[2] || 17;
  document.documentElement.style.setProperty("--text-size", `${size}px`);
}

// ---------------------------------------------------------------- reading the server

function profileFrom(id, d) {
  return { id, uid: d.uid, name: d.name || id, bio: d.bio || "", hue: d.hue ?? hueFor(id), iconURL: d.iconURL || null,
    backgroundURL: d.backgroundURL || null, hasBackground: d.hasBackground ?? true, birthday: d.birthday?.toDate?.() || null,
    updatedAt: d.updatedAt?.toDate?.() || new Date(0) };
}

function user(id) {
  if (id === S.account) return S.me;
  const p = S.profiles[id] || { id, name: id, bio: "", hue: hueFor(id) };
  const f = S.local.friends[id] || {};
  return { ...p, isFriend: !!S.friendIDs[id], addedAt: S.friendIDs[id] || new Date(0), favorite: !!f.favorite, hidden: !!f.hidden, blocked: !!f.blocked, nickname: f.nickname || null, displayName: f.nickname || p.name };
}
const displayName = (id) => (id === S.account ? S.me?.name : user(id).displayName) || id;

function watchUser(id) {
  if (!id || id === S.account || S.listeners[`user:${id}`]) return;
  S.listeners[`user:${id}`] = onSnapshot(doc(S.fb.db, "users", id), (snap) => {
    if (snap.exists()) { S.profiles[id] = profileFrom(id, snap.data()); refresh(); }
  }, () => {});
}

function messageFrom(id, d) {
  let kind = decodeKind(d.kind || "");
  if (!kind) return null;
  if (kind.type === "poll") kind.votes = d.votes || {};
  if (kind.type === "datePoll") kind.answers = d.answers || {};
  if (kind.type === "amida") kind.revealed = S.local.revealed.includes(id);
  const read = (d.readBy || []).filter((x) => x !== d.senderID);
  S.readBy[id] = d.readBy || [];
  return { id, senderID: d.senderID, kind, date: d.date?.toDate?.() || now(), replyTo: d.replyTo || null, silent: !!d.silent,
    edited: !!d.edited, reactions: d.reactions || {}, readCount: read.length };
}

function start(id, fb) {
  stop();
  S.account = id; S.fb = fb; S.uid = fb.auth.currentUser.uid;
  S.local = loadLocal(id);
  S.me = { id, name: id, bio: "", hue: hueFor(id) };
  saved.current = id;
  applyTheme();
  S.listeners.me = onSnapshot(doc(fb.db, "users", id), (snap) => {
    if (!snap.exists()) return;
    S.me = { ...profileFrom(id, snap.data()), displayName: snap.data().name || id };
    saved.remember(S.me);
    refresh();
  });
  S.listeners.friends = onSnapshot(collection(fb.db, "users", id, "friends"), (snap) => {
    S.friendIDs = {};
    snap.forEach((d) => { S.friendIDs[d.id] = d.data().addedAt?.toDate?.() || new Date(0); watchUser(d.id); });
    refresh();
  });
  S.listeners.requests = onSnapshot(collection(fb.db, "users", id, "requests"), async (snap) => {
    const first = !S.loaded.has("requests");
    S.loaded.add("requests");
    const next = {};
    snap.forEach((d) => { next[d.id] = d.data().at?.toDate?.() || now(); watchUser(d.id); });
    const fresh = Object.keys(next).filter((x) => !S.requestIDs[x] && !S.friendIDs[x]);
    S.requestIDs = next;
    refresh();
    if (!first) for (const from of fresh) {
      const s = await getDoc(doc(fb.db, "users", from)).catch(() => null);
      announce({ title: "友だち申請", body: `${s?.data()?.name || from}さんがあなたを友だちに追加しました`, userID: from });
    }
  });
  S.listeners.rooms = onSnapshot(query(collection(fb.db, "rooms"), where("memberUIDs", "array-contains", S.uid)), (snap) => {
    const seen = new Set();
    snap.forEach((d) => {
      const data = d.data();
      seen.add(d.id);
      S.rooms[d.id] = { id: d.id, title: data.title || null, members: data.members || [], isGroup: !!data.isGroup, isMynote: !!data.isMynote,
        iconURL: data.iconURL || null, backgroundURL: data.backgroundURL || null };
      (data.members || []).forEach(watchUser);
      const typing = data.typing || {};
      const fresh = Object.entries(typing).filter(([who, t]) => who !== S.account && Date.now() - t.toDate().getTime() < 7000);
      S.typing[d.id] = fresh.length ? fresh.sort((a, b) => b[1].toMillis() - a[1].toMillis())[0][0] : null;
      if (S.typing[d.id]) setTimeout(refreshRoomOnly, 7500);
      listenMessages(d.id);
    });
    for (const rid of Object.keys(S.rooms)) if (!seen.has(rid) && !S.pending[`room:${rid}`]) {
      delete S.rooms[rid];
      S.listeners[`messages:${rid}`]?.();
      delete S.listeners[`messages:${rid}`];
    }
    refresh();
  });
  showSplash(id);
  route();
}

function listenMessages(roomID) {
  if (S.listeners[`messages:${roomID}`]) return;
  S.listeners[`messages:${roomID}`] = onSnapshot(query(collection(S.fb.db, "rooms", roomID, "messages"), orderBy("date"), limitToLast(300)), (snap) => {
    const first = !S.loaded.has(roomID);
    S.loaded.add(roomID);
    const list = [];
    snap.forEach((d) => { const m = messageFrom(d.id, d.data()); if (m) list.push(m); });
    S.messages[roomID] = list;
    const arrived = new Set(list.map((m) => m.id));
    if (S.pending[roomID]) S.pending[roomID] = S.pending[roomID].filter((m) => !arrived.has(m.id));
    if (!first) snap.docChanges().forEach((c) => {
      if (c.type !== "added") return;
      const m = list.find((x) => x.id === c.doc.id);
      if (m) arrivedMessage(m, roomID);
    });
    if (S.openRoom === roomID && document.visibilityState === "visible") markRead(roomID);
    refresh();
  });
}

function stop() {
  for (const off of Object.values(S.listeners)) try { off(); } catch {}
  Object.assign(S, { account: null, fb: null, uid: null, me: null, profiles: {}, friendIDs: {}, requestIDs: {}, rooms: {}, messages: {}, readBy: {}, typing: {}, pending: {}, listeners: {}, loaded: new Set(), view: null, sheet: null, openRoom: null });
}

// ---------------------------------------------------------------- putting it together

function roomView(r) {
  const prefs = roomPrefs(r.id);
  const blocked = new Set(Object.entries(S.local.friends).filter(([, f]) => f.blocked).map(([k]) => k));
  let msgs = (S.messages[r.id] || []).filter((m) => m.date.getTime() > prefs.clearedAt && !prefs.deleted.includes(m.id) && !blocked.has(m.senderID));
  const sent = new Set(msgs.map((m) => m.id));
  msgs = msgs.concat((S.pending[r.id] || []).filter((m) => !sent.has(m.id)));
  const waiting = (S.local.scheduled[r.id] || []).map((m) => ({ ...m, date: new Date(m.date), scheduledAt: new Date(m.scheduledAt) }));
  const members = r.isMynote ? [S.account] : r.members.filter((x) => x !== S.account);
  const unread = S.openRoom === r.id ? 0 : msgs.filter((m) => m.senderID !== S.account && m.date.getTime() > prefs.lastRead).length;
  let hidden = prefs.hidden;
  if (!r.isGroup && !r.isMynote && S.local.friends[members[0]]?.blocked) hidden = true;
  return { ...r, members, messages: msgs, waiting, last: msgs[msgs.length - 1] || null, pinned: prefs.pinned, muted: prefs.muted, hidden, draft: prefs.draft, unread };
}
const rooms = () => Object.values(S.rooms).map(roomView);
function roomName(r) {
  if (r.isMynote) return "Mynote";
  if (r.title) return r.title;
  return r.members[0] ? displayName(r.members[0]) : "トーク";
}
function iconUser(r) {
  if (r.isMynote) return { id: "__mynote", name: "Mynote", mynote: true };
  if (r.isGroup) return { id: r.id, name: r.title || "G", hue: hueFor(r.id), iconURL: r.iconURL, backgroundURL: r.backgroundURL, hasBackground: true };
  return r.members[0] ? user(r.members[0]) : S.me;
}
function visibleRooms() {
  const sortKey = (r) => {
    const ms = r.members.map(user);
    if (S.local.talkSort === "added") return Math.max(0, ...ms.map((u) => +u.addedAt || 0));
    if (S.local.talkSort === "profile") return Math.max(0, ...ms.map((u) => +u.updatedAt || 0));
    return r.last ? +r.last.date : 0;
  };
  const fav = (r) => !r.isGroup && !r.isMynote && r.members.some((x) => S.local.friends[x]?.favorite);
  return rooms().filter((r) => !r.hidden).sort((a, b) => {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
    if (S.local.favoritesFirst && fav(a) !== fav(b)) return fav(a) ? -1 : 1;
    if (S.local.unreadFirst && (a.unread > 0) !== (b.unread > 0)) return a.unread > 0 ? -1 : 1;
    return sortKey(b) - sortKey(a) || a.id.localeCompare(b.id);
  });
}
function friends() {
  const list = Object.keys(S.friendIDs).map(user).filter((u) => !u.hidden && !u.blocked);
  return list.sort((a, b) => S.local.friendSort === "profile" ? (b.updatedAt || 0) - (a.updatedAt || 0) : b.addedAt - a.addedAt);
}
const requests = () => Object.keys(S.requestIDs).filter((x) => !S.friendIDs[x] && !S.local.friends[x]?.blocked).map(user);
const unreadTotal = () => rooms().filter((r) => !r.hidden && !r.muted).reduce((n, r) => n + r.unread, 0);
const mynote = () => rooms().find((r) => r.isMynote);

// ---------------------------------------------------------------- notifications

function announce(notice) {
  notice = { id: uuid(), date: Date.now(), seen: false, ...notice };
  S.local.notices.unshift(notice);
  S.local.notices = S.local.notices.slice(0, 100);
  saveLocal();
  if (!S.local.settings.notifications) return;
  if (document.visibilityState === "visible") {
    S.banner = notice;
    renderBanner();
  } else if ("Notification" in window && Notification.permission === "granted") {
    const n = new Notification(notice.title, { body: S.local.settings.showContent ? notice.body : "新しいメッセージがあります", tag: notice.id });
    n.onclick = () => { window.focus(); if (notice.roomID) openRoom(notice.roomID); n.close(); };
  }
}

function arrivedMessage(m, roomID) {
  if (m.senderID === S.account || S.openRoom === roomID) return;
  const prefs = roomPrefs(roomID);
  if (prefs.hidden) { prefs.hidden = false; saveLocal(); }
  if (prefs.muted || m.silent || S.local.friends[m.senderID]?.blocked) return;
  const r = S.rooms[roomID];
  const who = displayName(m.senderID);
  announce({ title: r?.isGroup ? `${roomName(roomView(r))}・${who}` : who, body: preview(m.kind), userID: m.senderID, roomID });
}

// ---------------------------------------------------------------- changes

function markRead(roomID) {
  const prefs = roomPrefs(roomID);
  prefs.lastRead = Date.now();
  saveLocal();
  const unread = (S.messages[roomID] || []).filter((m) => m.senderID !== S.account && !(S.readBy[m.id] || []).includes(S.account));
  if (!unread.length) return;
  unread.forEach((m) => (S.readBy[m.id] = [...(S.readBy[m.id] || []), S.account]));
  const batch = writeBatch(S.fb.db);
  unread.slice(-200).forEach((m) => batch.update(doc(S.fb.db, "rooms", roomID, "messages", m.id), { readBy: arrayUnion(S.account) }));
  batch.commit().catch(() => {});
}

async function fetchUser(id) {
  if (id === S.account) return S.me;
  const snap = await getDoc(doc(S.fb.db, "users", id)).catch(() => null);
  if (!snap?.exists()) return null;
  S.profiles[id] = profileFrom(id, snap.data());
  watchUser(id);
  return user(id);
}

async function addFriend(id) {
  S.friendIDs[id] = now();
  const f = friendPrefs(id); f.hidden = false; f.blocked = false;
  delete S.requestIDs[id];
  saveLocal(); watchUser(id); refresh();
  await setDoc(doc(S.fb.db, "users", S.account, "friends", id), { addedAt: Timestamp.now() }).catch(() => {});
  await deleteDoc(doc(S.fb.db, "users", S.account, "requests", id)).catch(() => {});
  await setDoc(doc(S.fb.db, "users", id, "requests", S.account), { at: Timestamp.now() }).catch(() => {});
  S.local.notices.unshift({ id: uuid(), date: Date.now(), title: "友だち追加", body: `${displayName(id)}を友だちに追加しました`, userID: id, seen: false });
  saveLocal();
}
async function decline(id) {
  delete S.requestIDs[id];
  refresh();
  await deleteDoc(doc(S.fb.db, "users", S.account, "requests", id)).catch(() => {});
}

const creating = {};
function roomWith(other) {
  const id = "dm_" + [S.account, other].sort().join("__");
  const prefs = roomPrefs(id);
  if (prefs.hidden) { prefs.hidden = false; saveLocal(); }
  if (!S.rooms[id]) {
    S.rooms[id] = { id, title: null, members: [S.account, other], isGroup: false, isMynote: false };
    S.pending[`room:${id}`] = true;
    creating[id] = (async () => {
      const u = await fetchUser(other);
      if (!u?.uid) return;
      await setDoc(doc(S.fb.db, "rooms", id), { members: [S.account, other], memberUIDs: [S.uid, u.uid], isGroup: false, isMynote: false, updatedAt: Timestamp.now() }, { merge: true }).catch(() => {});
      delete S.pending[`room:${id}`];
    })();
  }
  return id;
}

async function makeGroup(title, members) {
  const id = `g_${uuid()}`;
  S.rooms[id] = { id, title, members: [S.account, ...members], isGroup: true, isMynote: false };
  S.pending[`room:${id}`] = true;
  const uids = members.map((x) => S.profiles[x]?.uid).filter(Boolean);
  creating[id] = setDoc(doc(S.fb.db, "rooms", id), { members: [S.account, ...members], memberUIDs: [S.uid, ...uids], isGroup: true, isMynote: false, title, updatedAt: Timestamp.now() })
    .catch(() => {}).finally(() => delete S.pending[`room:${id}`]);
  return id;
}

async function uploadImage(file, path, side) {
  const blob = await shrink(file, side);
  const r = storageRef(S.fb.storage, `${path}-${uuid().slice(0, 8)}.jpg`);
  await uploadBytes(r, blob, { contentType: "image/jpeg" });
  return getDownloadURL(r);
}

/// Scales a picture down (and to a square centre for an icon) as JPEG.
async function shrink(file, side, square = false) {
  const bitmap = await createImageBitmap(file);
  let sx = 0, sy = 0, sw = bitmap.width, sh = bitmap.height;
  if (square) { const s = Math.min(sw, sh); sx = (sw - s) / 2; sy = (sh - s) / 2; sw = sh = s; }
  const scale = Math.min(1, side / Math.max(sw, sh));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(sw * scale); canvas.height = Math.round(sh * scale);
  canvas.getContext("2d").drawImage(bitmap, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
  return new Promise((ok) => canvas.toBlob(ok, "image/jpeg", 0.85));
}

async function send(roomID, kind, opts = {}) {
  const message = { id: uuid(), senderID: S.account, kind, date: now(), replyTo: opts.replyTo || null, silent: !!opts.silent, sending: true, reactions: {}, readCount: 0 };
  if (kind.type === "photo" && opts.file) message.localURL = URL.createObjectURL(opts.file);
  if (opts.at && opts.at > now()) {
    (S.local.scheduled[roomID] ||= []).push({ ...message, sending: false, date: +opts.at, scheduledAt: +opts.at });
    saveLocal(); refresh();
    return;
  }
  (S.pending[roomID] ||= []).push(message);
  roomPrefs(roomID).draft = "";
  saveLocal(); refresh();
  await upload(message, roomID, opts.file);
}

async function upload(message, roomID, file) {
  try {
    await creating[roomID];
    let kind = message.kind;
    if (kind.type === "photo" && file) {
      kind = { type: "remotePhoto", url: await uploadImage(file, `rooms/${roomID}/${message.id}`, 2048) };
    } else if (kind.type === "file" && file) {
      const r = storageRef(S.fb.storage, `rooms/${roomID}/files/${message.id}/${file.name}`);
      await uploadBytes(r, file, { contentType: file.type || "application/octet-stream" });
      kind = { type: "remoteFile", name: file.name, url: await getDownloadURL(r), size: file.size };
    }
    const fields = { senderID: message.senderID, senderUID: S.uid, date: Timestamp.fromDate(message.date), kind: encodeKind(kind), silent: message.silent, edited: false, readBy: [] };
    if (message.replyTo) fields.replyTo = message.replyTo;
    await setDoc(doc(S.fb.db, "rooms", roomID, "messages", message.id), fields);
    updateDoc(doc(S.fb.db, "rooms", roomID), "updatedAt", Timestamp.now(), new FieldPath("typing", S.account), deleteField()).catch(() => {});
  } catch (e) {
    S.pending[roomID] = (S.pending[roomID] || []).filter((m) => m.id !== message.id);
    refresh();
    toast("送信できませんでした");
  }
}

const change = (roomID, id, ...fields) => updateDoc(doc(S.fb.db, "rooms", roomID, "messages", id), ...fields).catch(() => toast("できませんでした"));
const react = (roomID, m, emoji) => change(roomID, m.id, new FieldPath("reactions", S.account), m.reactions[S.account] === emoji || !emoji ? deleteField() : emoji);
function vote(roomID, m, option) {
  if (m.kind.deadline && m.kind.deadline <= now()) return;
  let mine = [...(m.kind.votes[S.account] || [])];
  mine = mine.includes(option) ? mine.filter((x) => x !== option) : m.kind.multiple ? [...mine, option] : [option];
  change(roomID, m.id, new FieldPath("votes", S.account), mine.length ? mine : deleteField());
}
function answer(roomID, m, date, value) {
  if (m.kind.deadline && m.kind.deadline <= now()) return;
  const mine = [...(m.kind.answers[S.account] || m.kind.dates.map(() => -1))];
  mine[date] = mine[date] === value ? -1 : value;
  change(roomID, m.id, new FieldPath("answers", S.account), mine);
}

let lastTyped = 0;
function typed(roomID) {
  if (Date.now() - lastTyped < 3000 || S.rooms[roomID]?.isMynote) return;
  lastTyped = Date.now();
  updateDoc(doc(S.fb.db, "rooms", roomID), new FieldPath("typing", S.account), Timestamp.now()).catch(() => {});
}

function deliverDue() {
  if (!S.account) return;
  for (const [roomID, list] of Object.entries(S.local.scheduled)) {
    for (const m of list.filter((x) => x.scheduledAt <= Date.now())) {
      S.local.scheduled[roomID] = S.local.scheduled[roomID].filter((x) => x.id !== m.id);
      saveLocal();
      const message = { ...m, date: now(), sending: true };
      delete message.scheduledAt;
      (S.pending[roomID] ||= []).push(message);
      upload(message, roomID);
    }
  }
}
setInterval(deliverDue, 5000);

// ---------------------------------------------------------------- avatars

function avatar(u, size = 52, mark = "") {
  const s = `width:${size}px;height:${size}px;font-size:${size * 0.44}px`;
  let inner;
  if (u?.mynote) {
    inner = `<div class="avatar" style="${s};background:linear-gradient(135deg,#065A8C,#043e61)">${icon("note").replace("svg ", "svg ")}</div>`;
    inner = inner.replace('class="svg ', `style="width:${size * 0.45}px;height:${size * 0.45}px;color:#fff" class="svg `);
  } else {
    const h = Math.round((u?.hue ?? 0.58) * 360);
    const bg = `linear-gradient(135deg,hsl(${h} 55% 72%),hsl(${(h + 29) % 360} 65% 55%))`;
    inner = `<div class="avatar" style="${s};background:${bg}"><span>${esc([...(u?.name || "?")][0] || "?")}</span>${u?.iconURL ? `<img src="${esc(u.iconURL)}" alt="" loading="lazy">` : ""}</div>`;
  }
  return mark ? `<div class="avatar-wrap">${inner}<span class="mark">${icon(mark, "fill")}</span></div>` : inner;
}
const backdropURL = (u) => u?.backgroundURL || (u?.hasBackground !== false ? u?.iconURL : null);

// ---------------------------------------------------------------- routing and rendering

function route() {
  const m = location.pathname.match(/\/tooc\/@([a-z0-9._]{4,20})/i);
  if (m && S.account) {
    history.replaceState(null, "", "/tooc/");
    openSheet({ type: "find", id: m[1].toLowerCase() });
  }
}

function refresh() {
  if (!S.account) return;
  if (S.view?.type === "room") refreshRoomOnly();
  else if (!S.view) renderTabs();
  else renderView();
  if (S.sheet?.live) renderSheet();
}
function refreshRoomOnly() { if (S.view?.type === "room") renderMessages(); }

function render() {
  if (!configured) {
    $app.innerHTML = `<div class="login"><div class="logo"><h1>tooc</h1><p>まだ準備中です（config.js が空です）</p></div></div>`;
    return;
  }
  if (!S.account) return renderLogin();
  if (S.view?.type === "room") return renderRoom();
  if (S.view) return renderView();
  renderTabs();
}

// ---------- login

function renderLogin(mode = "create") {
  const list = saved.list;
  // Someone's link (ffui.me/tooc/@ID) opened without signing in: offer the app first.
  const linked = location.pathname.match(/\/tooc\/@([a-z0-9._]{4,20})/i)?.[1];
  $app.innerHTML = `
  <div class="login">
    ${linked ? `<div class="box" style="padding:16px;display:grid;gap:10px;justify-items:center;text-align:center"><b>@${esc(linked)} を友だちに追加</b><a class="btn" href="withdays://tooc?add=${encodeURIComponent(linked)}">tooc（アプリ）で開く</a><span class="hint">または下でログインすると、この Web 版で追加できます</span></div>` : ""}
    <div class="logo"><h1>tooc</h1><p id="lhint">${mode === "create" ? "toocIDとパスワードを決めるだけではじめられます" : "toocIDとパスワードでログイン"}</p></div>
    <div class="segmented" style="justify-self:center"><button data-mode="create" class="${mode === "create" ? "on" : ""}">新規登録</button><button data-mode="login" class="${mode === "login" ? "on" : ""}">ログイン</button></div>
    <div class="group">
      <label><span style="color:var(--text2)">@</span><input id="lid" type="text" autocomplete="username" autocapitalize="none" spellcheck="false" placeholder="toocID"></label>
      <label><input id="lpw" type="password" autocomplete="${mode === "create" ? "new-password" : "current-password"}" placeholder="パスワード"></label>
    </div>
    ${mode === "create" ? `<div class="hint">toocIDは半角英数字と . _ の4〜20文字、パスワードは8文字以上です。</div>` : ""}
    <button id="lgo" class="btn wide">${mode === "create" ? "アカウントを作成" : "ログイン"}</button>
    ${list.length ? `<div class="section-title">この端末のアカウント</div><div class="group">${list.map((a) => `<div class="item link" data-switch="${esc(a.id)}"><span style="display:flex;gap:12px;align-items:center">${avatar(a, 36)}<span><b>${esc(a.name)}</b><br><small style="color:var(--text2)">@${esc(a.id)}</small></span></span>${icon("chevron", "chev")}</div>`).join("")}</div>` : ""}
  </div>`;
  $app.querySelectorAll("[data-mode]").forEach((b) => (b.onclick = () => renderLogin(b.dataset.mode)));
  $app.querySelectorAll("[data-switch]").forEach((b) => (b.onclick = () => switchTo(b.dataset.switch)));
  const go = async () => {
    const id = $app.querySelector("#lid").value.trim().toLowerCase().replace(/^@/, "");
    const pw = $app.querySelector("#lpw").value;
    if (!REPLIES_OK.test(id) || pw.length < (mode === "create" ? 8 : 1)) return toast(mode === "create" ? "toocIDかパスワードの形が違います" : "toocIDとパスワードを入れてください");
    $app.querySelector("#lgo").disabled = true;
    try { mode === "create" ? await createAccount(id, pw) : await logIn(id, pw); }
    catch (e) { toast(describe(e)); $app.querySelector("#lgo").disabled = false; }
  };
  $app.querySelector("#lgo").onclick = go;
  $app.querySelector("#lpw").onkeydown = (e) => e.key === "Enter" && go();
}

function describe(e) {
  const code = e?.code || "";
  if (/wrong-password|invalid-credential|user-not-found|invalid-email/.test(code)) return "toocIDかパスワードが違います。";
  if (/email-already-in-use/.test(code)) return "このtoocIDはもう使われています。";
  if (/weak-password/.test(code)) return "パスワードが短すぎます。";
  if (/network/.test(code)) return "ネットにつながっていません。";
  if (/requires-recent-login/.test(code)) return "一度ログインし直してからもう一度お試しください。";
  return e?.message || "できませんでした。";
}

async function createAccount(id, pw) {
  const fb = appFor(id);
  const cred = await createUserWithEmailAndPassword(fb.auth, email(id), pw);
  try {
    if ((await getDoc(doc(fb.db, "users", id))).exists()) { await deleteUser(cred.user); throw { message: "このtoocIDはもう使われています。" }; }
    await setDoc(doc(fb.db, "users", id), { uid: cred.user.uid, name: id, bio: "", hue: Math.random(), updatedAt: Timestamp.now() });
    await setDoc(doc(fb.db, "rooms", `note_${id}`), { members: [id], memberUIDs: [cred.user.uid], isGroup: false, isMynote: true, updatedAt: Timestamp.now() });
  } catch (e) { if (!e.code) throw e; await deleteUser(cred.user).catch(() => {}); throw e; }
  signedIn(id, fb);
}
async function logIn(id, pw) {
  const fb = appFor(id);
  await signInWithEmailAndPassword(fb.auth, email(id), pw);
  signedIn(id, fb);
}
function signedIn(id, fb) {
  if (S.account && S.account !== id) saved.previous = S.account;
  if (!saved.list.some((a) => a.id === id)) saved.list = [...saved.list, { id, name: id, hue: hueFor(id) }];
  start(id, fb);
  render();
}
async function switchTo(id) {
  if (id === S.account) return;
  const fb = appFor(id);
  await fb.auth.authStateReady();
  if (!fb.auth.currentUser) { renderLogin("login"); $app.querySelector("#lid").value = id; toast("パスワードを入れてください"); return; }
  if (S.account) saved.previous = S.account;
  start(id, fb);
  render();
}
async function logOut() {
  const id = S.account;
  if (!id) return;
  saved.previous = id;
  await signOut(S.fb.auth).catch(() => {});
  stop();
  saved.current = null;
  render();
}

function showSplash(id) {
  const el = document.createElement("div");
  el.className = "splash";
  el.innerHTML = `<div><h1>tooc</h1><p>ようこそ、${esc(S.me?.name || id)}</p></div>`;
  document.body.append(el);
  setTimeout(() => el.remove(), 2000);
}

// ---------- tabs

function topbar(left, right, center = "") {
  return `<div class="topbar">${left ? `<div class="pill glass">${left}</div>` : ""}${center}<div class="spacer"></div>${right ? `<div class="pill glass">${right}</div>` : ""}</div>`;
}
const btn = (act, name, label, extra = "") => `<button data-act="${act}" ${extra} aria-label="${esc(label)}" title="${esc(label)}">${icon(name)}</button>`;

function renderTabs() {
  const t = S.tab;
  const left = btn("calendar", "back", "戻る") + (t !== "me" ? btn(t === "talk" ? "sortTalk" : "sortFriends", "sort", "並び替え") : "");
  const right = t === "me" ? btn("addMenu", "plus", "友だち追加") + btn("notices", "bell", "お知らせ") + btn("settings", "gear", "設定")
    : btn("search", "search", "検索") + btn("plusMenu", "plus", "追加") + btn("moreMenu", "more", "その他");
  const body = t === "talk" ? talkList() : t === "friends" ? friendList() : meTab();
  const unread = unreadTotal();
  const keep = S.renderedTab === t ? $app.querySelector("#tabscroll")?.scrollTop || 0 : 0;
  S.renderedTab = t;
  $app.innerHTML = `
    ${topbar(left, right)}
    <div class="scroll" id="tabscroll">${body}</div>
    <nav class="tabbar glass">
      ${[["talk", "トーク", "message"], ["friends", "友だち", "people"], ["me", "じぶん", "face"]].map(([k, l, i]) =>
        `<button data-tab="${k}" class="${t === k ? "on" : ""}">${icon(i, t === k ? "fill-soft" : "")}${l}${k === "talk" && unread ? `<span class="badge">${unread > 99 ? "99+" : unread}</span>` : ""}</button>`).join("")}
    </nav>`;
  $app.querySelector("#tabscroll").scrollTop = keep;
  bindTabs();
}

function talkList() {
  const list = visibleRooms().filter((r) => S.filter === "all" || (S.filter === "groups" ? r.isGroup : !r.isGroup && !r.isMynote));
  const seg = `<div class="segments"><div class="segmented">${[["all", "すべて"], ["friends", "友だち"], ["groups", "グループ"]].map(([k, l]) => `<button data-filter="${k}" class="${S.filter === k ? "on" : ""}">${l}</button>`).join("")}</div></div>`;
  if (!list.length) return seg + `<div class="empty">${icon("message")}<div>${S.filter === "groups" ? "グループはまだありません" : "トークはまだありません"}</div></div>`;
  return seg + list.map((r) => {
    const last = r.last;
    const icons = [r.draft ? icon("pencil", "mini") : "", r.muted ? icon("muted", "mini") : "", r.waiting.length ? icon("clock", "mini") : ""].join("");
    const pv = last ? `${last.sending ? "⏳ " : ""}${(() => { const s = last.senderID === S.account ? S.me : user(last.senderID); return s?.iconURL ? `<img class="inline" src="${esc(s.iconURL)}" alt="">` : ""; })()} ${esc(preview(last.kind))}` : `<span class="start-talk" data-start="${r.id}">トークを始めよう</span>`;
    return `<div class="row" data-room="${r.id}">
      <div data-avatar="${r.id}">${avatar(iconUser(r), 52, r.pinned ? "pin" : "")}</div>
      <div class="body"><div class="name"><span class="n">${esc(roomName(r))}</span>${r.isGroup ? `<span class="count small">${r.members.length + 1}</span>` : ""}${icons}</div><div class="preview">${pv}</div></div>
      <div class="side">${last ? `<span class="time">${listLabel(last.date)}</span>` : ""}${r.unread ? `<span class="count" style="opacity:${r.muted ? 0.45 : 1}">${r.unread > 999 ? "999+" : r.unread}</span>` : ""}</div>
    </div>`;
  }).join("");
}

function friendList() {
  const reqs = requests();
  const list = friends();
  let html = "";
  if (reqs.length) html += `<div class="section-title">友だち申請</div>` + reqs.map((u) => `
    <div class="row" data-profile="${esc(u.id)}">${avatar(u)}<div class="body" style="justify-content:center"><div class="name"><span class="n">${esc(u.displayName)}</span></div><div class="preview">@${esc(u.id)}</div></div>
    <button class="btn" data-accept="${esc(u.id)}" style="height:34px;padding:0 14px">友だちになる</button><button class="icon-button" data-decline="${esc(u.id)}" aria-label="申請を削除" style="color:var(--text2)">${icon("x")}</button></div>`).join("");
  if (!list.length && !reqs.length) return `<div class="empty">${icon("people")}<div>友だちはまだいません</div></div>`;
  html += list.map((u) => `
    <div class="row" data-profile="${esc(u.id)}">${avatar(u, 52, u.favorite ? "star" : "")}
      <div class="body" style="justify-content:${u.bio ? "flex-start" : "center"}"><div class="name"><span class="n">${esc(u.displayName)}</span></div>${u.bio ? `<div class="preview">${esc(u.bio)}</div>` : ""}</div>
      <button class="icon-button" data-talk="${esc(u.id)}" aria-label="トークを始める">${icon("message")}</button></div>`).join("");
  return html;
}

function meTab() {
  const me = S.me;
  const waiting = rooms().flatMap((r) => r.waiting.map((m) => ({ r, m }))).sort((a, b) => a.m.scheduledAt - b.m.scheduledAt);
  const note = mynote();
  const favs = friends().filter((u) => u.favorite);
  const bd = backdropURL(me);
  return `<div class="me">
    <div class="card" data-act="myProfile">
      ${bd ? `<div class="backdrop" style="background-image:url('${esc(bd)}')"></div>` : ""}<div class="veil"></div>
      <div class="inner"><div style="display:flex;gap:16px;align-items:center">${avatar(me, 76)}<div style="min-width:0"><h2>${esc(me.name)}</h2><div class="id" data-act="toggleID">@${esc(me.id)}</div></div></div>
      ${me.bio ? `<div class="bio">${esc(me.bio)}</div>` : ""}</div>
    </div>
    <div><div style="font-weight:700;margin:0 4px 10px">友だち追加</div>
      <div class="box split"><button data-act="myQR">${icon("qr")}QRコード</button><span class="divider"></span><button data-act="findID">${icon("at")}toocID</button></div></div>
    <div style="padding:0 4px">
      <div class="line-row" data-act="openNote">${avatar({ mynote: true }, 40)}<div style="flex:1;min-width:0"><div class="t">Mynote</div><div class="d">${esc(note?.last ? preview(note.last.kind) : "メモを書こう")}</div></div>${icon("chevron", "chev")}</div>
      <div class="line-row" data-act="scheduled"><div class="avatar" style="width:40px;height:40px;background:var(--accent)">${icon("clock")}</div><div style="flex:1;min-width:0"><div class="t">送信予約</div><div class="d">${waiting.length ? `${waiting.length}件・次は${candidate(waiting[0].m.scheduledAt)}` : "予約はありません"}</div></div>${icon("chevron", "chev")}</div>
    </div>
    <div class="box">
      <div class="line-row" data-act="toFriends" style="padding:16px"><span style="color:var(--accent)">${icon("people")}</span><div style="flex:1"><div class="t">友だち</div><div class="d">${friends().length}人の友だち</div></div>${icon("chevron", "chev")}</div>
      ${favs.length ? `<div style="border-top:.5px solid var(--sep)"><div class="section-title" style="padding-left:16px">★ お気に入り</div><div class="favs">${favs.map((u) => `<button data-talk="${esc(u.id)}">${avatar(u, 52)}<span>${esc(u.displayName)}</span></button>`).join("")}</div></div>` : ""}
    </div>
  </div>`;
}

function bindTabs() {
  $app.querySelectorAll("[data-tab]").forEach((b) => {
    let pressTimer, lastTap = 0;
    b.onclick = () => { S.tab = b.dataset.tab; renderTabs(); };
    // じぶん: hold for accounts, double-tap for the one used before.
    if (b.dataset.tab === "me") {
      b.onpointerdown = () => (pressTimer = setTimeout(() => { pressTimer = null; openSheet({ type: "accounts" }); }, 450));
      b.onpointerup = b.onpointerleave = () => clearTimeout(pressTimer);
      b.addEventListener("click", () => { if (Date.now() - lastTap < 320) switchBack(); lastTap = Date.now(); });
    }
  });
  $app.querySelectorAll("[data-filter]").forEach((b) => (b.onclick = () => { S.filter = b.dataset.filter; renderTabs(); }));
  $app.querySelectorAll("[data-room]").forEach((row) => {
    row.onclick = (e) => {
      if (e.target.closest("[data-avatar]")) return;
      if (e.target.closest("[data-start]")) { roomPrefs(row.dataset.room).draft = "よろしく！"; saveLocal(); }
      openRoom(row.dataset.room);
    };
    row.oncontextmenu = (e) => { e.preventDefault(); roomMenu(row.dataset.room, e); };
    longPress(row, (e) => roomMenu(row.dataset.room, e));
  });
  $app.querySelectorAll("[data-avatar]").forEach((a) => (a.onclick = () => {
    const r = roomView(S.rooms[a.dataset.avatar]);
    if (r.isMynote) openProfile(S.account); else if (!r.isGroup) openProfile(r.members[0]); else openRoom(r.id);
  }));
  $app.querySelectorAll("[data-profile]").forEach((r) => (r.onclick = (e) => { if (!e.target.closest("button")) openProfile(r.dataset.profile); }));
  $app.querySelectorAll("[data-talk]").forEach((b) => (b.onclick = (e) => { e.stopPropagation(); openRoom(roomWith(b.dataset.talk)); }));
  $app.querySelectorAll("[data-accept]").forEach((b) => (b.onclick = (e) => { e.stopPropagation(); addFriend(b.dataset.accept); }));
  $app.querySelectorAll("[data-decline]").forEach((b) => (b.onclick = (e) => { e.stopPropagation(); decline(b.dataset.decline); }));
  bindActs($app);
}

function longPress(el, fn) {
  let timer, start;
  el.addEventListener("touchstart", (e) => { start = e.touches[0]; timer = setTimeout(() => { timer = null; navigator.vibrate?.(10); fn({ clientX: start.clientX, clientY: start.clientY, target: e.target }); }, 450); }, { passive: true });
  el.addEventListener("touchmove", (e) => { if (timer && Math.hypot(e.touches[0].clientX - start.clientX, e.touches[0].clientY - start.clientY) > 10) clearTimeout(timer); }, { passive: true });
  el.addEventListener("touchend", (e) => { if (timer === null) e.preventDefault(); clearTimeout(timer); });
}

async function switchBack() {
  const prev = saved.previous;
  if (!prev || prev === S.account || !saved.list.some((a) => a.id === prev)) return toast("前に使ったアカウントがありません");
  await switchTo(prev);
}

// ---------- actions shared by bars and sheets

const ACTS = {
  calendar: () => toast("Web 版にはカレンダーはありません"),
  sortTalk: (e) => popMenu(e, [
    { title: `${S.local.favoritesFirst ? "✓ " : ""}お気に入りを優先`, run: () => { S.local.favoritesFirst = !S.local.favoritesFirst; saveLocal(); refresh(); } },
    { title: `${S.local.unreadFirst ? "✓ " : ""}未読メッセージを優先`, run: () => { S.local.unreadFirst = !S.local.unreadFirst; saveLocal(); refresh(); } },
    ...[["added", "友だち追加が新しい順"], ["conversation", "会話が新しい順"], ["profile", "Myprofileの更新が新しい順"]].map(([k, l]) => ({ title: `${S.local.talkSort === k ? "✓ " : ""}${l}`, run: () => { S.local.talkSort = k; saveLocal(); refresh(); } })),
  ]),
  sortFriends: (e) => popMenu(e, [["added", "友だち追加が新しい順"], ["conversation", "会話が新しい順"], ["profile", "Myprofileの更新が新しい順"]].map(([k, l]) => ({ title: `${S.local.friendSort === k ? "✓ " : ""}${l}`, run: () => { S.local.friendSort = k; saveLocal(); refresh(); } }))),
  search: () => openView({ type: "search" }),
  plusMenu: (e) => popMenu(e, [
    { title: "トークルームを作成", icon: "message", run: () => openSheet({ type: "newTalk", group: false }) },
    { title: "グループを作成", icon: "people", run: () => openSheet({ type: "newTalk", group: true }) },
    { title: "MyQRを表示", icon: "qr", run: () => openSheet({ type: "qr" }) },
    { title: "toocIDで検索", icon: "at", run: () => openSheet({ type: "find", id: "" }) },
  ]),
  addMenu: (e) => popMenu(e, [
    { title: "MyQRを表示", icon: "qr", run: () => openSheet({ type: "qr" }) },
    { title: "toocIDで検索", icon: "at", run: () => openSheet({ type: "find", id: "" }) },
  ]),
  moreMenu: (e) => popMenu(e, [
    { title: "すべて既読にする", icon: "check", run: () => { rooms().filter((r) => r.unread).forEach((r) => markRead(r.id)); refresh(); } },
    { title: "設定", icon: "gear", run: () => openView({ type: "settings" }) },
  ]),
  notices: () => openView({ type: "notices" }),
  settings: () => openView({ type: "settings" }),
  myProfile: () => openProfile(S.account),
  toggleID: (e) => { e.stopPropagation(); const el = e.target.closest("[data-act]"); el.textContent = el.textContent.startsWith("@•") ? `@${S.account}` : "@••••••"; },
  myQR: () => openSheet({ type: "qr" }),
  findID: () => openSheet({ type: "find", id: "" }),
  openNote: () => { const n = mynote(); if (n) openRoom(n.id); },
  scheduled: () => openView({ type: "scheduled" }),
  toFriends: () => { S.tab = "friends"; renderTabs(); },
  back: () => closeView(),
};
function bindActs(root) {
  root.querySelectorAll("[data-act]").forEach((el) => (el.onclick = (e) => { const f = ACTS[el.dataset.act]; if (f) f(e); }));
}

function popMenu(e, items, anchor) {
  closeMenu();
  const back = document.createElement("div");
  back.className = "menu-back";
  back.onclick = closeMenu;
  const menu = document.createElement("div");
  menu.className = "menu glass";
  menu.innerHTML = items.map((it, i) => `<button data-i="${i}" class="${it.danger ? "danger" : ""}"><span>${esc(it.title)}</span>${it.icon ? icon(it.icon) : ""}</button>`).join("");
  $layer.append(back, menu);
  const rect = (anchor || e?.target?.closest?.("button,.row,.msg") || document.body).getBoundingClientRect();
  const w = 240, h = items.length * 46;
  let x = Math.min(Math.max(12, (e?.clientX ?? rect.left) - w / 2), innerWidth - w - 12);
  let y = rect.bottom + 8;
  if (y + h > innerHeight - 12) y = Math.max(12, rect.top - h - 8);
  Object.assign(menu.style, { left: `${x}px`, top: `${y}px`, width: `${w}px` });
  menu.querySelectorAll("[data-i]").forEach((b) => (b.onclick = () => { closeMenu(); items[+b.dataset.i].run(); }));
  return menu;
}
function closeMenu() { $layer.innerHTML = ""; }

function roomMenu(roomID, e) {
  const r = roomView(S.rooms[roomID]);
  const items = [{ title: "開く", icon: "message", run: () => openRoom(roomID) }];
  if (r.unread) items.push({ title: "既読にする", icon: "check", run: () => { markRead(roomID); refresh(); } });
  items.push({ title: r.pinned ? "ピン留めを外す" : "ピン留め", icon: "pin", run: () => { roomPrefs(roomID).pinned = !r.pinned; saveLocal(); refresh(); } });
  if (!r.isMynote) items.push({ title: r.muted ? "通知をオン" : "通知をオフ", icon: "bell", run: () => { roomPrefs(roomID).muted = !r.muted; saveLocal(); refresh(); } });
  items.push({ title: "非表示", icon: "eyeoff", run: () => confirmBox("トークを非表示にしますか？", "", "非表示", () => { roomPrefs(roomID).hidden = true; saveLocal(); refresh(); }) });
  if (!r.isMynote) items.push({ title: "削除", icon: "trash", danger: true, run: () => confirmBox("トークを削除しますか？", "元に戻せません。", "削除", () => { const p = roomPrefs(roomID); p.hidden = true; p.clearedAt = Date.now(); saveLocal(); refresh(); }) });
  // A peek of the talk above the menu; tapping it opens the talk.
  const menu = popMenu(e, items, e.target.closest(".row"));
  const peek = document.createElement("div");
  peek.className = "menu glass";
  const top = Math.max(12, parseFloat(menu.style.top) - 330);
  Object.assign(peek.style, { left: menu.style.left, width: "300px", height: "300px", top: `${top}px`, cursor: "pointer", overflow: "hidden" });
  peek.innerHTML = `<div style="display:flex;gap:8px;align-items:center;padding:10px 12px;border-bottom:.5px solid var(--sep)">${avatar(iconUser(r), 28)}<b>${esc(roomName(r))}</b></div><div class="messages" style="padding:8px;height:256px;overflow:hidden;justify-content:flex-end">${messagesHTML(r, true)}</div>`;
  peek.onclick = () => { closeMenu(); openRoom(roomID); };
  if (parseFloat(menu.style.top) > 340) $layer.append(peek);
}

function confirmBox(title, message, button, run) {
  const back = document.createElement("div");
  back.className = "sheet-back";
  back.style.alignItems = "center";
  back.innerHTML = `<div class="glass" style="width:270px;border-radius:16px;overflow:hidden;text-align:center;animation:pop .2s">
    <div style="padding:18px 16px 14px"><b>${esc(title)}</b>${message ? `<div style="font-size:13px;margin-top:4px">${esc(message)}</div>` : ""}</div>
    <div style="display:flex;border-top:.5px solid var(--sep)"><button style="flex:1;padding:12px;color:var(--accent)" data-no>キャンセル</button><button style="flex:1;padding:12px;color:var(--red);font-weight:600;border-left:.5px solid var(--sep)" data-yes>${esc(button)}</button></div></div>`;
  document.body.append(back);
  back.querySelector("[data-no]").onclick = () => back.remove();
  back.querySelector("[data-yes]").onclick = () => { back.remove(); run(); };
}

// ---------- pushed screens

function openView(v) { S.view = v; render(); }
function closeView() {
  if (S.view?.type === "room") {
    roomPrefs(S.openRoom).draft = S.draft; saveLocal();
    S.openRoom = null; S.replyTo = null; S.editing = null; S.attachments = [];
  }
  S.view = S.view?.back || null;
  render();
}
function openRoom(id) {
  closeSheet();
  S.openRoom = id;
  S.draft = roomPrefs(id).draft || "";
  S.view = { type: "room", id };
  markRead(id);
  if (S.banner?.roomID === id) S.banner = null;
  render();
}

function renderView() {
  const v = S.view;
  const page = { search: searchView, notices: noticesView, scheduled: scheduledView, settings: settingsView }[v.type];
  if (!page) return;
  const { title, body, right = "" } = page();
  $app.innerHTML = `${topbar(btn("back", "back", "戻る"), right, `<div class="title glass pill" style="padding:0 14px">${esc(title)}</div>`)}<div class="scroll">${body}</div>`;
  bindActs($app);
  page.bind?.();
  if (v.type === "search") {
    const input = $app.querySelector("#q");
    input.value = v.q || "";
    input.focus();
    input.oninput = () => { v.q = input.value; const box = $app.querySelector("#results"); box.innerHTML = searchResults(v.q); bindResults(box); };
    bindResults($app.querySelector("#results"));
  }
  if (v.type === "settings") bindSettings();
}

function searchView() {
  return { title: "検索", body: `<div class="form"><div class="group"><label>${icon("search")}<input id="q" type="search" placeholder="トーク・友だち・メッセージ"></label></div></div><div id="results">${searchResults(S.view.q || "")}</div>` };
}
function searchResults(q) {
  q = q.trim().toLowerCase();
  if (!q) return "";
  const rs = visibleRooms();
  const roomsHit = rs.filter((r) => roomName(r).toLowerCase().includes(q));
  const friendsHit = friends().filter((u) => u.displayName.toLowerCase().includes(q) || u.id.includes(q));
  const msgs = rs.flatMap((r) => r.messages.filter((m) => m.kind.type === "text" && m.kind.text.toLowerCase().includes(q)).reverse().map((m) => ({ r, m })));
  if (!roomsHit.length && !friendsHit.length && !msgs.length) return `<div class="empty">「${esc(q)}」は見つかりませんでした</div>`;
  return (roomsHit.length ? `<div class="section-title">トーク</div>` + roomsHit.map((r) => `<div class="row" style="height:60px" data-goroom="${r.id}">${avatar(iconUser(r), 40)}<div class="name">${esc(roomName(r))}</div></div>`).join("") : "")
    + (friendsHit.length ? `<div class="section-title">友だち</div>` + friendsHit.map((u) => `<div class="row" style="height:60px" data-goprofile="${esc(u.id)}">${avatar(u, 40)}<div><div class="name">${esc(u.displayName)}</div><div class="preview">@${esc(u.id)}</div></div></div>`).join("") : "")
    + (msgs.length ? `<div class="section-title">メッセージ</div>` + msgs.map(({ r, m }) => `<div class="row" style="height:68px" data-goroom="${r.id}">${avatar(iconUser(r), 40)}<div class="body" style="height:auto"><div class="name"><span class="n">${esc(roomName(r))}</span><span style="margin-left:auto;font-weight:400;font-size:12px;color:var(--text2)">${listLabel(m.date)}</span></div><div class="preview">${esc(m.kind.text)}</div></div></div>`).join("") : "");
}
function bindResults(box) {
  box.querySelectorAll("[data-goroom]").forEach((r) => (r.onclick = () => { S.view = null; openRoom(r.dataset.goroom); }));
  box.querySelectorAll("[data-goprofile]").forEach((r) => (r.onclick = () => openProfile(r.dataset.goprofile)));
}

function noticesView() {
  S.local.notices.forEach((n) => (n.seen = true)); saveLocal();
  const list = S.local.notices;
  const right = list.length ? btn("clearNotices", "trash", "すべて削除") : "";
  ACTS.clearNotices = () => { S.local.notices = []; saveLocal(); renderView(); };
  const body = list.length ? list.map((n) => `<div class="row" style="height:auto;min-height:64px;align-items:flex-start" data-notice="${n.id}">
      ${n.userID ? avatar(user(n.userID), 40) : `<div class="avatar" style="width:40px;height:40px;background:var(--card);color:var(--accent)">${icon("bell")}</div>`}
      <div style="flex:1;min-width:0"><div style="display:flex"><b style="flex:1">${esc(n.title)}</b><span style="font-size:12px;color:var(--text2)">${listLabel(new Date(n.date))}</span></div>
      <div class="preview">${esc(S.local.settings.showContent ? n.body : "新しいお知らせがあります")}</div></div></div>`).join("")
    : `<div class="empty">${icon("bell")}<div>お知らせはありません</div></div>`;
  noticesView.bind = () => $app.querySelectorAll("[data-notice]").forEach((el) => (el.onclick = () => {
    const n = list.find((x) => x.id === el.dataset.notice);
    if (n?.roomID && S.rooms[n.roomID]) { S.view = null; openRoom(n.roomID); } else if (n?.userID) openProfile(n.userID);
  }));
  return { title: "お知らせ", body, right };
}

function scheduledView() {
  const list = rooms().flatMap((r) => r.waiting.map((m) => ({ r, m }))).sort((a, b) => a.m.scheduledAt - b.m.scheduledAt);
  scheduledView.bind = () => {
    $app.querySelectorAll("[data-now]").forEach((b) => (b.onclick = () => { const [rid, mid] = b.dataset.now.split("|"); const m = S.local.scheduled[rid].find((x) => x.id === mid); m.scheduledAt = Date.now(); deliverDue(); renderView(); }));
    $app.querySelectorAll("[data-cancel]").forEach((b) => (b.onclick = () => { const [rid, mid] = b.dataset.cancel.split("|"); S.local.scheduled[rid] = S.local.scheduled[rid].filter((x) => x.id !== mid); saveLocal(); renderView(); }));
  };
  return {
    title: "送信予約",
    body: list.length ? list.map(({ r, m }) => `<div class="row" style="height:auto;min-height:72px">${avatar(iconUser(r), 40)}
      <div style="flex:1;min-width:0"><div style="display:flex;gap:6px"><b style="flex:1">${esc(roomName(r))}</b><span style="font-size:12px;color:var(--accent)">${candidate(m.scheduledAt)}</span></div><div class="preview">${esc(preview(m.kind))}</div>
      <div style="display:flex;gap:8px;margin-top:6px"><button class="btn" style="height:30px;font-size:13px" data-now="${r.id}|${m.id}">今すぐ送信</button><button class="btn danger" style="height:30px;font-size:13px" data-cancel="${r.id}|${m.id}">取り消す</button></div></div></div>`).join("")
      : `<div class="empty">${icon("clock")}<div>送信予約はありません</div></div>`,
  };
}

function settingsView() {
  const s = S.local.settings;
  const sub = S.view.page;
  if (sub === "account") return { title: "アカウント", body: `<div class="form">
    <div class="group"><div class="item">toocID<span style="margin-left:auto;color:var(--text2)">@${esc(S.account)}</span></div><div class="item link" data-page="password">パスワードを変更${icon("chevron", "chev")}</div></div>
    <div class="group"><div class="item link" data-do="logout" style="color:var(--accent)">ログアウト</div></div>
    <div class="group"><div class="item link danger" data-do="delete">アカウントを削除</div></div></div>` };
  if (sub === "password") return { title: "パスワードを変更", body: `<div class="form"><div class="group"><label><input id="pw0" type="password" placeholder="いまのパスワード" autocomplete="current-password"></label></div>
    <div class="group"><label><input id="pw1" type="password" placeholder="新しいパスワード" autocomplete="new-password"></label><label><input id="pw2" type="password" placeholder="もう一度" autocomplete="new-password"></label></div><div class="hint">8文字以上</div>
    <button class="btn wide" data-do="password">変更する</button></div>` };
  if (sub === "notifications") return { title: "通知", body: `<div class="form"><div class="group">
    <label>通知<input class="toggle" type="checkbox" data-set="notifications" ${s.notifications ? "checked" : ""}></label>
    <label>メッセージの内容を表示<input class="toggle" type="checkbox" data-set="showContent" ${s.showContent ? "checked" : ""} ${s.notifications ? "" : "disabled"}></label></div></div>` };
  if (sub === "hidden") {
    const hiddenFriends = Object.keys(S.friendIDs).map(user).filter((u) => u.hidden && !u.blocked);
    const blocked = Object.keys(S.local.friends).filter((k) => S.local.friends[k].blocked).map(user);
    const hiddenRooms = rooms().filter((r) => r.hidden);
    const block = (title, list, label, kind) => `<div class="section-title">${title}</div><div class="group">${list.length ? list.map((x) => `<div class="item">${avatar(kind === "room" ? iconUser(x) : x, 36)}<span style="flex:1">${esc(kind === "room" ? roomName(x) : x.displayName)}</span><button class="btn secondary" style="height:30px;font-size:13px" data-undo="${kind}|${esc(x.id)}">${label}</button></div>`).join("") : `<div class="item" style="color:var(--text2)">ありません</div>`}</div>`;
    return { title: "非表示・ブロック", body: `<div class="form">${block("非表示の友だち", hiddenFriends, "再表示", "friend")}${block("ブロック中", blocked, "ブロック解除", "block")}${block("非表示のトーク", hiddenRooms, "再表示", "room")}</div>` };
  }
  if (sub === "talk") return { title: "トーク", body: `<div class="form">
    <div class="section-title">文字サイズ</div><div class="segmented" style="justify-self:start">${SIZES.map(([k, l]) => `<button data-size="${k}" class="${s.textSize === k ? "on" : ""}">${l}</button>`).join("")}</div>
    <div class="section-title">テーマ</div><div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px">${THEMES.map(([k, l]) => `<button data-theme="${k}" style="display:grid;gap:6px;justify-items:center;font-size:12px;color:${s.theme === k ? "var(--accent)" : "var(--text2)"};font-weight:${s.theme === k ? 700 : 400}"><span style="width:100%;height:64px;border-radius:14px;border:${s.theme === k ? "2.5px solid var(--accent)" : ".5px solid var(--sep)"}" class="theme-swatch-${k}"></span>${l}</button>`).join("")}</div>
    <div class="group"><label>改行キーで送信<input class="toggle" type="checkbox" data-set="returnSends" ${s.returnSends ? "checked" : ""}></label></div></div>` };
  return { title: "設定", body: `<div class="form">
    <div class="group"><div class="item link" data-do="editProfile"><span style="display:flex;gap:14px;align-items:center">${avatar(S.me, 56)}<span><b>${esc(S.me.name)}</b><br><small style="color:var(--text2)">@${esc(S.account)}</small></span></span><span style="color:var(--accent)">編集</span></div></div>
    <div class="group">${[["account", "アカウント", "user"], ["notifications", "通知", "bell"], ["hidden", "非表示・ブロック", "eyeoff"], ["talk", "トーク", "message"]].map(([k, l, i]) => `<div class="item link" data-page="${k}"><span style="display:flex;gap:12px;align-items:center;color:var(--text)"><span style="color:var(--accent)">${icon(i)}</span>${l}</span>${icon("chevron", "chev")}</div>`).join("")}</div></div>` };
}
function bindSettings() {
  $app.querySelectorAll("[data-page]").forEach((el) => (el.onclick = () => openView({ type: "settings", page: el.dataset.page, back: S.view })));
  $app.querySelectorAll("[data-set]").forEach((el) => (el.onchange = () => {
    S.local.settings[el.dataset.set] = el.checked; saveLocal();
    if (el.dataset.set === "notifications" && el.checked && "Notification" in window) Notification.requestPermission();
    renderView();
  }));
  $app.querySelectorAll("[data-size]").forEach((el) => (el.onclick = () => { S.local.settings.textSize = el.dataset.size; saveLocal(); applyTheme(); renderView(); }));
  $app.querySelectorAll("[data-theme]").forEach((el) => (el.onclick = () => { S.local.settings.theme = el.dataset.theme; saveLocal(); applyTheme(); renderView(); }));
  THEMES.forEach(([k]) => { const sw = $app.querySelector(`.theme-swatch-${k}`); if (sw) { const prev = document.documentElement.dataset.theme; document.documentElement.dataset.theme = k; const cs = getComputedStyle(document.documentElement); sw.style.background = `linear-gradient(180deg, ${cs.getPropertyValue("--bg")} 0 40%, ${cs.getPropertyValue("--mine")} 40% 70%, ${cs.getPropertyValue("--theirs")} 70%)`; document.documentElement.dataset.theme = prev; } });
  $app.querySelectorAll("[data-undo]").forEach((el) => (el.onclick = () => {
    const [kind, id] = el.dataset.undo.split("|");
    if (kind === "friend") friendPrefs(id).hidden = false;
    if (kind === "block") friendPrefs(id).blocked = false;
    if (kind === "room") roomPrefs(id).hidden = false;
    saveLocal(); renderView();
  }));
  $app.querySelectorAll("[data-do]").forEach((el) => (el.onclick = async () => {
    const what = el.dataset.do;
    if (what === "editProfile") openSheet({ type: "editProfile" });
    if (what === "logout") confirmBox("ログアウトしますか？", "", "ログアウト", logOut);
    if (what === "delete") confirmBox("アカウントを削除しますか？", "元に戻せません。", "削除", async () => {
      try {
        const id = S.account, fb = S.fb;
        for (const f of Object.keys(S.friendIDs)) await deleteDoc(doc(fb.db, "users", id, "friends", f)).catch(() => {});
        await deleteDoc(doc(fb.db, "rooms", `note_${id}`)).catch(() => {});
        await deleteDoc(doc(fb.db, "users", id));
        await deleteUser(fb.auth.currentUser);
        localStorage.removeItem(`tooc.local.${id}`); saved.forget(id); stop(); saved.current = null; render();
      } catch (e) { toast(describe(e)); }
    });
    if (what === "password") {
      const [a, b, c] = ["#pw0", "#pw1", "#pw2"].map((x) => $app.querySelector(x).value);
      if (b.length < 8 || b !== c) return toast("新しいパスワードを確かめてください");
      try {
        await reauthenticateWithCredential(S.fb.auth.currentUser, EmailAuthProvider.credential(email(S.account), a));
        await updatePassword(S.fb.auth.currentUser, b);
        toast("パスワードを変更しました"); closeView();
      } catch (e) { toast(describe(e)); }
    }
  }));
}

// ---------- room

function renderRoom() {
  const r = roomView(S.rooms[S.view.id] || { id: S.view.id, members: [] });
  const right = btn("roomSearch", "search", "トーク内を検索") + btn("roomMenu", "more", "その他");
  const name = `<div class="title" style="pointer-events:auto">${esc(roomName(r))}${r.isGroup ? ` <small>(${r.members.length + 1})</small>` : ""}</div>`;
  $app.innerHTML = `<div class="room">${topbar(btn("back", "back", "戻る"), right, name)}<div class="messages" id="messages"></div><div id="composer"></div></div>`;
  ACTS.roomSearch = () => openSheet({ type: "roomSearch", roomID: r.id });
  ACTS.roomMenu = (e) => roomSettingsMenu(e, r);
  bindActs($app);
  renderMessages(true);
  renderComposer();
}

function roomSettingsMenu(e, r) {
  const items = [];
  if (r.isGroup) {
    items.push({ title: "メンバー", icon: "people", run: () => openSheet({ type: "members", roomID: r.id }) });
    items.push({ title: "グループプロフィールを編集", icon: "pencil", run: () => openSheet({ type: "groupEdit", roomID: r.id }) });
  } else if (!r.isMynote) items.push({ title: "プロフィール", icon: "user", run: () => openProfile(r.members[0]) });
  items.push({ title: r.pinned ? "ピン留めを外す" : "ピン留め", icon: "pin", run: () => { roomPrefs(r.id).pinned = !r.pinned; saveLocal(); } });
  if (!r.isMynote) {
    items.push({ title: r.muted ? "通知をオン" : "通知をオフ", icon: "bell", run: () => { roomPrefs(r.id).muted = !r.muted; saveLocal(); } });
    items.push({ title: "非表示", icon: "eyeoff", run: () => confirmBox("トークを非表示にしますか？", "", "非表示", () => { roomPrefs(r.id).hidden = true; saveLocal(); closeView(); }) });
  }
  items.push({ title: "トーク履歴を削除", icon: "trash", danger: true, run: () => confirmBox("トーク履歴を削除しますか？", "元に戻せません。", "削除", () => { roomPrefs(r.id).clearedAt = Date.now(); saveLocal(); refresh(); }) });
  if (r.isGroup) items.push({ title: "グループを退会", icon: "back", danger: true, run: () => confirmBox("グループを退会しますか？", "", "退会", async () => {
    await updateDoc(doc(S.fb.db, "rooms", r.id), { members: arrayRemove(S.account), memberUIDs: arrayRemove(S.uid) }).catch(() => {});
    delete S.rooms[r.id]; closeView();
  }) });
  popMenu(e, items);
}

function messagesHTML(r, peek = false) {
  const list = peek ? r.messages.slice(-12) : r.messages;
  const out = [];
  let lastDay = null;
  const burst = (a, b) => a && b && a.senderID === b.senderID && a.kind.type !== "unsent" && b.kind.type !== "unsent" && Math.floor(+a.date / 60000) === Math.floor(+b.date / 60000) && sameDay(a.date, b.date);
  list.forEach((m, i) => {
    const day = startOfDay(m.date).getTime();
    if (!peek && day !== lastDay) { out.push(`<div class="day">${dayLabel(m.date)}</div>`); lastDay = day; }
    const prev = list[i - 1], next = list[i + 1];
    const first = !burst(prev, m) || (!peek && startOfDay(prev.date).getTime() !== day);
    const last = !burst(m, next);
    out.push(messageHTML(r, m, first, last, first ? false : prev.kind.type === "text" && m.kind.type === "text", last ? false : next.kind.type === "text" && m.kind.type === "text"));
  });
  if (!peek) {
    const typer = S.typing[r.id];
    if (typer) out.push(`<div class="typing">${avatar(user(typer), 36)}<div class="dots bubble tail" style="margin:0 0 0 var(--tail)"><i></i><i></i><i></i></div></div>`);
    if (r.waiting.length) {
      out.push(`<div class="scheduled-title">送信予約</div>`);
      r.waiting.forEach((m) => out.push(`<div class="msg mine waiting" data-waiting="${m.id}"><div class="meta">${candidate(m.scheduledAt)}</div><div class="bubble">${esc(preview(m.kind))}</div></div>`));
    }
  }
  return out.join("");
}

function messageHTML(r, m, first, last, joinedAbove, joinedBelow) {
  const mine = m.senderID === S.account;
  if (m.kind.type === "unsent") return `<div class="unsent">${mine ? "送信を取り消しました" : `${esc(displayName(m.senderID))}が送信を取り消しました`}</div>`;
  const read = !r.isMynote && mine && m.readCount ? (r.isGroup ? `既読${m.readCount}` : "既読") : "";
  const meta = m.sending ? `<div class="meta">送信中</div>` : last ? `<div class="meta">${m.edited ? "<span>編集済み</span>" : ""}${m.silent || read ? `<span>${m.silent ? "🔕 " : ""}${read}</span>` : ""}<span>${clock(m.date)}</span></div>` : "";
  const reacts = Object.values(m.reactions || {});
  const counts = {};
  reacts.forEach((e) => (counts[e] = (counts[e] || 0) + 1));
  const reactHTML = reacts.length ? `<span class="reactions ${m.reactions[S.account] ? "mine-on" : ""}" data-unreact="${m.id}">${Object.entries(counts).map(([e, n]) => `${e}${n > 1 ? `<small>${n}</small>` : ""}`).join(" ")}</span>` : "";
  const body = bubbleHTML(r, m, mine, first, joinedAbove, joinedBelow);
  const sender = user(m.senderID);
  if (mine) return `<div class="msg mine ${first ? "first" : ""}" data-msg="${m.id}" style="opacity:${m.sending ? 0.6 : 1}"><div class="col"><div class="line">${body}${meta}</div>${reactHTML}</div></div>`;
  return `<div class="msg theirs ${first ? "first" : ""}" data-msg="${m.id}">
    <div class="avatar-slot">${first ? `<div data-who="${esc(m.senderID)}" style="cursor:pointer">${avatar(sender, 36)}</div>` : ""}</div>
    <div class="col">${first && r.isGroup ? `<div class="sender">${esc(sender.displayName)}</div>` : ""}<div class="line">${body}${meta}</div>${reactHTML}</div></div>`;
}

function bubbleHTML(r, m, mine, first, joinedAbove, joinedBelow) {
  const k = m.kind;
  if (k.type === "text") {
    const quoted = m.replyTo && r.messages.find((x) => x.id === m.replyTo);
    const long = k.text.split("\n").length > 14 || k.text.length > 600;
    const cls = ["bubble", first ? "tail" : "", joinedAbove ? "join-top" : "", joinedBelow ? "join-bottom" : "", mine ? "mine-shape" : "theirs-shape", long ? "clamp" : ""].join(" ");
    return `<div class="${cls}">${quoted ? `<div class="quote"><div><b>${esc(displayName(quoted.senderID))}</b>${esc(preview(quoted.kind)).slice(0, 60)}</div></div>` : ""}<div class="text">${linkify(esc(k.text))}</div>${long ? `<button class="more" data-full="${m.id}">すべてを表示</button>` : ""}</div>`;
  }
  if (k.type === "photo" || k.type === "remotePhoto") {
    const src = k.url || (m.localURL ?? "");
    return src ? `<img class="photo" src="${esc(src)}" alt="写真" data-zoom="${esc(src)}" loading="lazy">` : `<div class="photo" style="display:grid;place-items:center">${icon("photo")}</div>`;
  }
  return `<div class="cardmsg">${cardHTML(r, m)}</div>`;
}

const linkify = (html) => html.replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>');

function deadlineHTML(d) {
  if (!d) return "";
  const closed = d <= now();
  return `<div class="small-note ${closed ? "closed" : ""}">${closed ? "締め切りました" : `締め切り ${candidate(d)}`}</div>`;
}

function cardHTML(r, m) {
  const k = m.kind;
  switch (k.type) {
    case "file": case "remoteFile":
      return `<a href="${esc(k.url || "#")}" target="_blank" rel="noopener" download="${esc(k.name)}" style="display:flex;gap:10px;align-items:center;color:inherit;text-decoration:none"><span class="avatar" style="width:40px;height:40px;background:var(--accent)">${icon("doc")}</span><span><b>${esc(k.name)}</b><br><small style="color:var(--text2)">${bytes(k.size || 0)}</small></span></a>`;
    case "location":
      return `<a href="https://maps.apple.com/?ll=${k.latitude},${k.longitude}&q=${encodeURIComponent(k.title)}" target="_blank" rel="noopener" style="color:inherit;text-decoration:none;display:grid;gap:8px">
        <iframe title="地図" style="width:100%;height:130px;border:0;border-radius:12px;pointer-events:none" loading="lazy" src="https://www.openstreetmap.org/export/embed.html?bbox=${k.longitude - 0.004},${k.latitude - 0.003},${k.longitude + 0.004},${k.latitude + 0.003}&marker=${k.latitude},${k.longitude}"></iframe>
        <b>📍 ${esc(k.title)}</b></a>`;
    case "poll": {
      const votes = k.votes || {};
      const total = Math.max(1, Object.keys(votes).length);
      const mine = votes[S.account] || [];
      const closed = k.deadline && k.deadline <= now();
      return `<div class="head">${icon("chart")}投票${k.multiple ? "（複数選択）" : ""}</div><h4>${esc(k.question)}</h4>${deadlineHTML(k.deadline)}
        ${k.options.map((o, i) => { const n = Object.values(votes).filter((v) => v.includes(i)).length; return `<button class="opt ${mine.includes(i) ? "on" : ""}" data-vote="${m.id}|${i}" ${closed ? "disabled" : ""}><span class="bar" style="width:${(n / total) * 100}%"></span><span>${mine.includes(i) ? "●" : "○"}</span><span>${esc(o)}</span><span class="n">${n}</span></button>`; }).join("")}
        <div class="small-note">${Object.keys(votes).length}人が投票</div>`;
    }
    case "datePoll": {
      const answers = k.answers || {};
      const mine = answers[S.account] || [];
      const closed = k.deadline && k.deadline <= now();
      const count = (i, v) => Object.values(answers).filter((a) => a[i] === v).length;
      return `<div class="head">${icon("calendar")}日程調整</div><h4>${esc(k.title)}</h4>${deadlineHTML(k.deadline)}
        ${k.dates.map((d, i) => `<div style="display:grid;gap:4px"><div style="display:flex"><span style="flex:1">${candidate(d)}</span><small style="color:var(--text2)">○${count(i, 2)} △${count(i, 1)} ×${count(i, 0)}</small></div>
          <div class="answers">${[[2, "○"], [1, "△"], [0, "×"]].map(([v, l]) => `<button class="${mine[i] === v ? "on" : ""}" data-answer="${m.id}|${i}|${v}" ${closed ? "disabled" : ""}>${l}</button>`).join("")}</div></div>`).join("")}
        <div class="small-note">${Object.keys(answers).length}人が回答</div>`;
    }
    case "amida":
      return `<div class="head">${icon("ladder")}あみだくじ</div><h4>${esc(k.title)}</h4>${deadlineHTML(k.deadline)}
        ${k.revealed ? k.entrants.map((e, i) => `<div style="display:flex"><span style="flex:1">${esc(e)}</span><b style="color:var(--accent)">${esc(k.prizes[amidaWalk(k, i).at(-1)])}</b></div>`).join("") : `<div class="small-note">${k.entrants.length}人が参加</div>`}
        <button style="color:var(--accent);font-weight:600" data-amida="${m.id}">${k.revealed ? "もう一度見る" : "結果を見る"}</button>`;
    default:
      return "";
  }
}

function amidaWalk(a, start) {
  let col = start;
  const path = [col];
  for (let level = 0; level < 9; level++) {
    if (a.rungs.some((x) => x.level === level && x.column === col)) col += 1;
    else if (a.rungs.some((x) => x.level === level && x.column === col - 1)) col -= 1;
    path.push(col);
  }
  return path;
}
function makeRungs(n) {
  const rungs = [];
  for (let level = 0; level < 9; level++) for (let c = 0; c < n - 1; ) { if (Math.random() < 0.5) { rungs.push({ level, column: c }); c += 2; } else c += 1; }
  for (let c = 0; c < n - 1; c++) if (!rungs.some((x) => x.column === c)) { const level = Math.floor(Math.random() * 9); if (!rungs.some((x) => x.level === level && Math.abs(x.column - c) <= 1)) rungs.push({ level, column: c }); }
  return rungs;
}

function renderMessages(first = false) {
  const box = $app.querySelector("#messages");
  if (!box) return;
  const r = roomView(S.rooms[S.view.id] || { id: S.view.id, members: [] });
  const atBottom = first || box.scrollHeight - box.scrollTop - box.clientHeight < 80;
  const keep = box.scrollTop;
  box.innerHTML = r.messages.length || r.waiting.length ? messagesHTML(r) : `<button class="start-talk" style="margin:auto" data-hello>トークを始めよう</button>`;
  if (atBottom) box.scrollTop = box.scrollHeight; else box.scrollTop = keep;
  bindMessages(box, r);
  const composer = $app.querySelector("#composer");
  if (composer && (composer.dataset.mode || "") !== composerMode(r)) renderComposer();
}

function bindMessages(box, r) {
  box.querySelector("[data-hello]")?.addEventListener("click", () => { S.draft = "よろしく！"; renderComposer(); $app.querySelector("textarea")?.focus(); });
  box.querySelectorAll("[data-who]").forEach((a) => (a.onclick = () => openProfile(a.dataset.who)));
  box.querySelectorAll("[data-zoom]").forEach((img) => (img.onclick = () => zoom(img.dataset.zoom)));
  box.querySelectorAll("[data-full]").forEach((b) => (b.onclick = () => { const m = r.messages.find((x) => x.id === b.dataset.full); openSheet({ type: "fullText", text: m.kind.text, title: displayName(m.senderID) }); }));
  box.querySelectorAll("[data-vote]").forEach((b) => (b.onclick = () => { const [id, i] = b.dataset.vote.split("|"); vote(r.id, r.messages.find((x) => x.id === id), +i); }));
  box.querySelectorAll("[data-answer]").forEach((b) => (b.onclick = () => { const [id, i, v] = b.dataset.answer.split("|"); answer(r.id, r.messages.find((x) => x.id === id), +i, +v); }));
  box.querySelectorAll("[data-amida]").forEach((b) => (b.onclick = () => openSheet({ type: "amida", roomID: r.id, id: b.dataset.amida })));
  box.querySelectorAll("[data-unreact]").forEach((b) => (b.onclick = () => { const m = r.messages.find((x) => x.id === b.dataset.unreact); if (m.reactions[S.account]) react(r.id, m, null); }));
  box.querySelectorAll("[data-waiting]").forEach((el) => (el.oncontextmenu = el.onclick = (e) => { e.preventDefault(); popMenu(e, [
    { title: "今すぐ送信", icon: "send", run: () => { const m = S.local.scheduled[r.id].find((x) => x.id === el.dataset.waiting); m.scheduledAt = Date.now(); deliverDue(); } },
    { title: "送信予約を取り消す", icon: "x", danger: true, run: () => { S.local.scheduled[r.id] = S.local.scheduled[r.id].filter((x) => x.id !== el.dataset.waiting); saveLocal(); refresh(); } },
  ]); }));
  box.querySelectorAll("[data-msg]").forEach((el) => {
    const m = r.messages.find((x) => x.id === el.dataset.msg);
    if (!m || m.sending) return;
    el.oncontextmenu = (e) => { e.preventDefault(); messageMenu(r, m, el); };
    longPress(el, () => messageMenu(r, m, el));
    // Swipe a bubble left to reply.
    let sx = null, dx = 0;
    el.addEventListener("touchstart", (e) => { sx = e.touches[0].clientX; dx = 0; }, { passive: true });
    el.addEventListener("touchmove", (e) => { if (sx === null) return; dx = Math.min(0, e.touches[0].clientX - sx); el.style.transform = `translateX(${-96 * (1 - Math.exp(dx / 96))}px)`; el.style.transition = "none"; if (dx < -64 && !el.dataset.armed) { el.dataset.armed = "1"; navigator.vibrate?.(8); } }, { passive: true });
    el.addEventListener("touchend", () => { el.style.transition = ""; el.style.transform = ""; if (dx < -64) setReply(m); sx = null; delete el.dataset.armed; });
  });
}

function messageMenu(r, m, el) {
  closeMenu();
  const rect = el.querySelector(".bubble,.photo,.cardmsg")?.getBoundingClientRect() || el.getBoundingClientRect();
  const mine = m.senderID === S.account;
  const back = document.createElement("div");
  back.className = "menu-back";
  back.onclick = closeMenu;
  const lifted = el.querySelector(".bubble,.photo,.cardmsg").cloneNode(true);
  lifted.classList.add("lifted");
  Object.assign(lifted.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, margin: 0 });
  // The reactions above the bubble, big and outside the menu; ⋯ for every emoji.
  const bar = document.createElement("div");
  bar.className = "emoji-bar glass";
  bar.innerHTML = S.local.settings.favoriteReactions.map((e) => `<button data-e="${e}">${e}</button>`).join("") + `<button class="more" data-e="more">⋯</button>`;
  const items = [{ title: "返信", icon: "reply", run: () => setReply(m) }];
  if (m.kind.type === "text") {
    items.push({ title: "コピー", icon: "copy", run: () => navigator.clipboard.writeText(m.kind.text).then(() => toast("コピーしました")) });
    if (mine) items.push({ title: "編集", icon: "pencil", run: () => { S.editing = m; S.replyTo = null; S.draft = m.kind.text; renderComposer(); $app.querySelector("textarea")?.focus(); } });
  }
  if (mine) items.push({ title: "送信取消", icon: "undo", danger: true, run: () => change(r.id, m.id, { kind: encodeKind({ type: "unsent" }), reactions: {} }) });
  items.push({ title: "削除", icon: "trash", danger: true, run: () => { roomPrefs(r.id).deleted.push(m.id); saveLocal(); refresh(); } });
  $layer.append(back, lifted, bar);
  const menu = document.createElement("div");
  menu.className = "menu glass";
  menu.innerHTML = items.map((it, i) => `<button data-i="${i}" class="${it.danger ? "danger" : ""}"><span>${esc(it.title)}</span>${icon(it.icon)}</button>`).join("");
  $layer.append(menu);
  const bw = bar.offsetWidth || 320, mw = 230, mh = items.length * 46;
  const x = (w) => Math.min(Math.max(12, mine ? rect.right - w : rect.left), innerWidth - w - 12);
  const below = rect.bottom + 10 + mh < innerHeight - 12;
  Object.assign(bar.style, { left: `${x(bw)}px`, top: `${Math.max(12, rect.top - 62 - (below ? 0 : mh + 10))}px` });
  Object.assign(menu.style, { left: `${x(mw)}px`, top: `${below ? rect.bottom + 10 : rect.top - mh - 10}px`, width: `${mw}px` });
  bar.querySelectorAll("[data-e]").forEach((b) => (b.onclick = () => { closeMenu(); b.dataset.e === "more" ? openSheet({ type: "emoji", roomID: r.id, id: m.id }) : react(r.id, m, b.dataset.e); }));
  menu.querySelectorAll("[data-i]").forEach((b) => (b.onclick = () => { closeMenu(); items[+b.dataset.i].run(); }));
}

function setReply(m) { S.replyTo = m; S.editing = null; renderComposer(); $app.querySelector("textarea")?.focus(); }

function composerMode(r) {
  const other = !r.isGroup && !r.isMynote ? r.members[0] : null;
  return other && !S.friendIDs[other] ? `stranger:${other}` : "input";
}

function renderComposer() {
  const box = $app.querySelector("#composer");
  if (!box) return;
  const r = roomView(S.rooms[S.view.id] || { id: S.view.id, members: [] });
  const mode = composerMode(r);
  box.dataset.mode = mode;
  if (mode.startsWith("stranger:")) {
    const id = mode.slice(9);
    box.innerHTML = `<div class="notfriend glass"><span style="flex:1">友だちになるまでメッセージは送れません</span><button class="btn" data-befriend>友だちになる</button></div>`;
    box.querySelector("[data-befriend]").onclick = () => addFriend(id).then(() => renderComposer());
    return;
  }
  const bars = [];
  if (S.replyTo) bars.push(`<div class="bar">${avatar(user(S.replyTo.senderID), 26)}<div class="grow"><b>${esc(displayName(S.replyTo.senderID))}へ返信</b><span>${esc(preview(S.replyTo.kind))}</span></div><button data-clear="reply" aria-label="返信をやめる">${icon("x")}</button></div>`);
  if (S.editing) bars.push(`<div class="bar"><span style="color:var(--accent)">${icon("pencil")}</span><div class="grow"><b>メッセージを編集</b></div><button data-clear="edit" aria-label="編集をやめる">${icon("x")}</button></div>`);
  if (S.attachments.length) bars.push(`<div class="attach">${S.attachments.map((a, i) => `<div class="tw"><img class="thumb" src="${a.url}" alt=""><button class="x" data-unattach="${i}" aria-label="添付を外す">✕</button></div>`).join("")}</div>`);
  box.innerHTML = `<div class="composer">
    <div class="tools glass"><button data-tool="plus" aria-label="追加">${icon("plus")}</button><button data-tool="photo" aria-label="写真">${icon("photo")}</button></div>
    <div class="field glass">${bars.join("")}<div class="row2"><textarea rows="1" placeholder="${esc(roomName(r))}へ送信"></textarea><button class="send hidden" data-send aria-label="送信">${icon(S.editing ? "check" : "send")}</button></div></div>
    <input type="file" accept="image/*" multiple hidden id="pickPhoto"><input type="file" accept="image/*" capture="environment" hidden id="pickCamera"><input type="file" hidden id="pickFile">
  </div>`;
  const ta = box.querySelector("textarea");
  const sendBtn = box.querySelector("[data-send]");
  ta.value = S.draft;
  const sync = () => {
    ta.style.height = "auto"; ta.style.height = `${Math.min(154, ta.scrollHeight)}px`;
    sendBtn.classList.toggle("hidden", !(ta.value.trim() || (S.attachments.length && !S.editing)));
  };
  sync();
  ta.oninput = () => { S.draft = ta.value; sync(); if (ta.value) typed(r.id); };
  ta.onkeydown = (e) => {
    if (e.key === "Enter" && !e.isComposing && (S.local.settings.returnSends ? !e.shiftKey : e.metaKey || e.ctrlKey)) { e.preventDefault(); submit(r); }
  };
  sendBtn.onclick = () => submit(r);
  sendBtn.oncontextmenu = (e) => { e.preventDefault(); sendMenu(e, r); };
  longPress(sendBtn, (e) => sendMenu(e, r));
  box.querySelectorAll("[data-clear]").forEach((b) => (b.onclick = () => { if (b.dataset.clear === "reply") S.replyTo = null; else { S.editing = null; S.draft = ""; } renderComposer(); }));
  box.querySelectorAll("[data-unattach]").forEach((b) => (b.onclick = () => { S.attachments.splice(+b.dataset.unattach, 1); renderComposer(); }));
  const attach = (files) => { for (const f of files) S.attachments.push({ file: f, url: URL.createObjectURL(f) }); renderComposer(); };
  box.querySelector("#pickPhoto").onchange = (e) => attach(e.target.files);
  box.querySelector("#pickCamera").onchange = (e) => attach(e.target.files);
  box.querySelector("#pickFile").onchange = (e) => { const f = e.target.files[0]; if (f) send(r.id, { type: "file", name: f.name, size: f.size }, { file: f, replyTo: S.replyTo?.id }); S.replyTo = null; };
  box.querySelector('[data-tool="photo"]').onclick = () => box.querySelector("#pickPhoto").click();
  box.querySelector('[data-tool="plus"]').onclick = (e) => popMenu(e, [
    { title: "カメラ", icon: "camera", run: () => box.querySelector("#pickCamera").click() },
    { title: "写真", icon: "photo", run: () => box.querySelector("#pickPhoto").click() },
    { title: "ファイル", icon: "doc", run: () => box.querySelector("#pickFile").click() },
    { title: "位置情報", icon: "mappin", run: () => sendLocation(r) },
    { title: "投票", icon: "chart", run: () => openSheet({ type: "poll", roomID: r.id }) },
    { title: "日程調整", icon: "calendar", run: () => openSheet({ type: "datePoll", roomID: r.id }) },
    { title: "あみだくじ", icon: "ladder", run: () => openSheet({ type: "amida-new", roomID: r.id }) },
    ...(S.draft.trim() && !S.attachments.length ? [{ title: "時刻指定して送信", icon: "clock", run: () => openSheet({ type: "schedule", roomID: r.id }) }] : []),
  ], box.querySelector('[data-tool="plus"]'));
}

function sendMenu(e, r) {
  if (S.editing) return;
  const items = [{ title: "ふつうに送信", icon: "send", run: () => submit(r) }];
  if (!r.isMynote) items.push({ title: "ミュートメッセージで送信", icon: "muted", run: () => submit(r, { silent: true }) });
  if (!S.attachments.length) items.push({ title: "時刻指定して送信", icon: "clock", run: () => openSheet({ type: "schedule", roomID: r.id }) });
  popMenu(e, items, e.target.closest("button"));
}

function submit(r, opts = {}) {
  const text = S.draft.trim();
  if (S.editing) {
    if (text) change(r.id, S.editing.id, { kind: encodeKind({ type: "text", text }), edited: true });
    S.editing = null;
  } else {
    if (!text && !S.attachments.length) return;
    const reply = S.replyTo?.id;
    for (const a of S.attachments) send(r.id, { type: "photo" }, { file: a.file, replyTo: reply, silent: opts.silent }).catch(() => {});
    if (text) send(r.id, { type: "text", text }, { replyTo: S.attachments.length ? null : reply, silent: opts.silent, at: opts.at });
    S.attachments = [];
    S.replyTo = null;
  }
  S.draft = "";
  roomPrefs(r.id).draft = ""; saveLocal();
  renderComposer();
  $app.querySelector("textarea")?.focus();
}

function sendLocation(r) {
  if (!navigator.geolocation) return toast("位置情報を使えません");
  navigator.geolocation.getCurrentPosition(
    (p) => send(r.id, { type: "location", latitude: p.coords.latitude, longitude: p.coords.longitude, title: "現在地" }),
    () => toast("位置情報を取得できませんでした"),
    { enableHighAccuracy: true, timeout: 10000 },
  );
}

function zoom(src) {
  const el = document.createElement("div");
  el.className = "zoom";
  el.innerHTML = `<img src="${esc(src)}" alt="写真"><a class="btn save glass" href="${esc(src)}" download target="_blank" rel="noopener">${icon("download")}保存</a>`;
  const img = el.querySelector("img");
  let scale = 1, x = 0, y = 0, sx, sy, dist;
  const apply = () => (img.style.transform = `translate(${x}px, ${y}px) scale(${scale})`);
  el.onclick = (e) => { if (e.target === el && scale === 1) el.remove(); };
  img.ondblclick = () => { scale = scale > 1 ? 1 : 2.5; x = y = 0; apply(); };
  el.onwheel = (e) => { e.preventDefault(); scale = Math.min(10, Math.max(1, scale * (e.deltaY < 0 ? 1.1 : 0.9))); if (scale === 1) x = y = 0; apply(); };
  el.addEventListener("touchstart", (e) => { if (e.touches.length === 2) dist = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY); else { sx = e.touches[0].clientX - x; sy = e.touches[0].clientY - y; } }, { passive: true });
  el.addEventListener("touchmove", (e) => {
    if (e.touches.length === 2) { const d = Math.hypot(e.touches[0].clientX - e.touches[1].clientX, e.touches[0].clientY - e.touches[1].clientY); scale = Math.min(10, Math.max(1, scale * d / dist)); dist = d; }
    else if (scale > 1) { x = e.touches[0].clientX - sx; y = e.touches[0].clientY - sy; }
    else { y = e.touches[0].clientY - sy; el.style.background = `rgba(0,0,0,${0.92 - Math.min(0.6, Math.abs(y) / 500)})`; }
    apply();
  }, { passive: true });
  el.addEventListener("touchend", () => { if (scale === 1 && Math.abs(y) > 100) el.remove(); else if (scale === 1) { y = 0; el.style.background = ""; apply(); } });
  document.body.append(el);
}

// ---------- profile

function openProfile(id) {
  closeMenu();
  const isMe = id === S.account;
  const u = isMe ? S.me : user(id);
  if (!isMe) watchUser(id);
  const el = document.createElement("div");
  el.className = "profile";
  const bd = backdropURL(u);
  const draw = () => {
    const u = isMe ? S.me : user(id);
    el.innerHTML = `<div class="frame">
      <div class="bg" style="${bd ? `background-image:url('${esc(bd)}')` : "background:linear-gradient(#383838,#141414)"}"></div><div class="shade"></div>
      ${topbar(`<button data-close aria-label="閉じる">${icon("x")}</button>`, isMe ? `<button data-edit aria-label="プロフィールを編集">${icon("pencil")}</button><button data-qr aria-label="MyQR">${icon("qr")}</button>`
        : u.isFriend && !u.blocked ? `<button data-talk aria-label="トーク">${icon("message")}</button>` : `<button data-add aria-label="友だち追加">${icon("plus")}</button>`)}
      <div class="center">
        <div data-icon style="cursor:zoom-in">${avatar(u, 112)}</div>
        <h2 data-name>${esc(u.displayName || u.name)}${u.nickname ? icon("pencil") : ""}</h2>
        ${u.bio ? `<p data-bio>${esc(u.bio)}</p>` : ""}
        ${u.birthday ? `<div class="bd">🎂 ${u.birthday.getMonth() + 1}月${u.birthday.getDate()}日</div>` : ""}
      </div></div>`;
    el.querySelector("[data-close]").onclick = () => el.remove();
    el.querySelector(".frame").onclick = (e) => { if (e.target.classList.contains("shade") || e.target.classList.contains("bg") || e.target === el.querySelector(".frame")) el.classList.toggle("clear"); };
    el.querySelector("[data-icon]").onclick = () => u.iconURL && zoom(u.iconURL);
    el.querySelector("[data-edit]")?.addEventListener("click", () => { el.remove(); openSheet({ type: "editProfile" }); });
    el.querySelector("[data-qr]")?.addEventListener("click", () => { el.remove(); openSheet({ type: "qr" }); });
    el.querySelector("[data-talk]")?.addEventListener("click", () => { el.remove(); openRoom(roomWith(id)); });
    el.querySelector("[data-add]")?.addEventListener("click", async () => { await addFriend(id); draw(); });
    el.querySelector("[data-bio]")?.addEventListener("click", () => detail(`<p style="font-size:17px;white-space:pre-wrap;margin:0">${esc(u.bio)}</p>`));
    el.querySelector("[data-name]").onclick = () => {
      const editable = !isMe && S.friendIDs[id];
      detail(`<h1 data-n>${esc(u.displayName || u.name)}</h1>${u.nickname ? `<div style="opacity:.7">本人の名前：${esc(u.name)}</div>` : ""}<div style="opacity:.6">@${esc(id)}</div>`, editable);
    };
  };
  const detail = (html, editable = false) => {
    const d = document.createElement("div");
    d.className = "detail";
    d.innerHTML = html;
    const frame = el.querySelector(".frame");
    const bar = document.createElement("div");
    bar.innerHTML = topbar(`<button data-back aria-label="戻る">${icon("back")}</button>`, editable ? `<button data-rename style="width:auto;padding:0 12px;font-weight:600">変更</button>` : "");
    d.prepend(bar.firstElementChild);
    frame.append(d);
    d.querySelector("[data-back]").onclick = () => d.remove();
    d.querySelector("[data-rename]")?.addEventListener("click", (e) => {
      const h = d.querySelector("[data-n]");
      if (e.target.textContent === "変更") {
        h.outerHTML = `<input data-input value="${esc(user(id).displayName)}">`;
        d.querySelector("[data-input]").focus();
        e.target.textContent = "完了";
      } else {
        const v = d.querySelector("[data-input]").value.trim();
        friendPrefs(id).nickname = v && v !== user(id).name ? v : null;
        saveLocal(); refresh(); d.remove(); draw();
      }
    });
  };
  draw();
  document.body.append(el);
}

// ---------- sheets

function openSheet(sheet) { closeMenu(); S.sheet = sheet; renderSheet(); }
function closeSheet() { document.querySelector(".sheet-back")?.remove(); S.sheet = null; }

function sheetFrame(title, body, { right = "", tall = false } = {}) {
  document.querySelector(".sheet-back")?.remove();
  const back = document.createElement("div");
  back.className = "sheet-back";
  back.innerHTML = `<div class="sheet ${tall ? "tall" : ""}"><header><button class="icon-button" data-x aria-label="閉じる">${icon("x")}</button><h3>${esc(title)}</h3><div style="min-width:40px;display:flex;justify-content:flex-end">${right}</div></header><div class="content">${body}</div></div>`;
  back.onclick = (e) => { if (e.target === back) closeSheet(); };
  back.querySelector("[data-x]").onclick = closeSheet;
  document.body.append(back);
  return back;
}

function renderSheet() {
  const s = S.sheet;
  if (!s) return;
  const f = SHEETS[s.type];
  if (f) f(s);
}

const SHEETS = {
  qr(s) {
    const link = `https://ffui.me/tooc/@${S.account}`;
    const q = qrcode(0, "M"); q.addData(link); q.make();
    const svg = q.createSvgTag({ cellSize: 6, margin: 0, scalable: true });
    const enc = encodeURIComponent(link);
    const back = sheetFrame("MyQR", `<div style="display:grid;gap:22px;padding:20px 0 10px;justify-items:center">
      <div class="qr">${svg}</div><b style="color:var(--text2)">@${esc(S.account)}</b>
      ${"BarcodeDetector" in window ? `<button class="btn" data-scan>${icon("scan")}スキャン</button>` : ""}
      <div class="share">
        <a href="https://line.me/R/share?text=${enc}" target="_blank" rel="noopener"><i style="background:#06C755">L</i>LINE</a>
        <a href="sms:&body=${enc}"><i style="background:#34C759">✉</i>iMessage</a>
        <a href="https://x.com/intent/post?text=${enc}" target="_blank" rel="noopener"><i style="background:#000">X</i>X</a>
        <a href="https://www.facebook.com/sharer/sharer.php?u=${enc}" target="_blank" rel="noopener"><i style="background:#1877F2">f</i>Facebook</a>
        <button data-copy><i style="background:#8e8e93">⧉</i>コピー</button>
        ${navigator.share ? `<button data-share><i style="background:#8e8e93">↑</i>その他</button>` : ""}
      </div></div>`, { tall: true });
    back.querySelector("[data-copy]").onclick = () => navigator.clipboard.writeText(link).then(() => toast("リンクをコピーしました"));
    back.querySelector("[data-share]")?.addEventListener("click", () => navigator.share({ url: link }));
    back.querySelector("[data-scan]")?.addEventListener("click", () => scanQR());
  },
  find(s) {
    const back = sheetFrame("toocIDで検索", `<div class="form"><div style="display:flex;gap:8px"><div class="group" style="flex:1;border-radius:22px"><label style="min-height:44px;padding:0 16px"><span style="color:var(--text2)">@</span><input id="fid" type="text" autocapitalize="none" spellcheck="false" placeholder="toocID"></label></div>
      <button class="send" style="width:44px;height:44px;margin:0" data-go aria-label="検索">${icon("search")}</button></div><div id="found"></div></div>`, { tall: true });
    const input = back.querySelector("#fid");
    input.value = s.id || "";
    const go = async () => {
      const id = input.value.trim().toLowerCase().replace(/^@/, "");
      const out = back.querySelector("#found");
      if (!REPLIES_OK.test(id)) { out.innerHTML = `<div class="hint" style="text-align:center">toocIDは半角英数字と . _ の4〜20文字です。</div>`; return; }
      const u = await fetchUser(id);
      if (!u) { out.innerHTML = `<div class="hint" style="text-align:center">@${esc(id)} は見つかりませんでした。</div>`; return; }
      const action = id === S.account ? `<div class="hint">あなたのtoocIDです</div>` : u.isFriend ? `<button class="btn" data-talk>${icon("message")}トーク</button>` : `<button class="btn" data-add>${icon("plus")}友だちに追加</button>`;
      out.innerHTML = `<div class="box" style="display:grid;justify-items:center;gap:12px;padding:24px">${avatar(u, 84)}<b style="font-size:20px">${esc(u.displayName || u.name)}</b><span style="color:var(--text2)">@${esc(id)}</span>${action}</div>`;
      out.querySelector("[data-talk]")?.addEventListener("click", () => openRoom(roomWith(id)));
      out.querySelector("[data-add]")?.addEventListener("click", async () => { await addFriend(id); go(); });
    };
    back.querySelector("[data-go]").onclick = go;
    input.onkeydown = (e) => e.key === "Enter" && go();
    if (s.id) go(); else input.focus();
  },
  newTalk(s) {
    const chosen = new Set();
    const list = friends().sort((a, b) => a.displayName.localeCompare(b.displayName));
    const back = sheetFrame(s.group ? "グループを作成" : "トークルームを作成", `<div class="form">${s.group ? `<div class="group"><label><input id="gname" type="text" placeholder="グループ名"></label></div>` : ""}
      <div class="group">${list.length ? list.map((u) => `<div class="item link" data-pick="${esc(u.id)}"><span style="display:flex;gap:12px;align-items:center">${avatar(u, 40)}${esc(u.displayName)}</span>${s.group ? `<span data-mark style="color:var(--text3)">○</span>` : ""}</div>`).join("") : `<div class="item" style="color:var(--text2)">友だちはまだいません</div>`}</div></div>`,
      { right: s.group ? `<button class="btn" style="height:34px" data-make>作成</button>` : "", tall: true });
    back.querySelectorAll("[data-pick]").forEach((el) => (el.onclick = () => {
      const id = el.dataset.pick;
      if (!s.group) return openRoom(roomWith(id));
      chosen.has(id) ? chosen.delete(id) : chosen.add(id);
      el.querySelector("[data-mark]").textContent = chosen.has(id) ? "●" : "○";
      el.querySelector("[data-mark]").style.color = chosen.has(id) ? "var(--accent)" : "var(--text3)";
    }));
    back.querySelector("[data-make]")?.addEventListener("click", async () => {
      if (!chosen.size) return toast("メンバーを選んでください");
      const names = [...chosen].map(displayName);
      const title = back.querySelector("#gname").value.trim() || names.slice(0, 3).join("、") + (names.length > 3 ? "…" : "");
      openRoom(await makeGroup(title, [...chosen]));
    });
  },
  members(s) {
    const r = roomView(S.rooms[s.roomID]);
    const back = sheetFrame(`メンバー（${r.members.length + 1}）`, `<div class="form"><div class="group"><div class="item">${avatar(S.me, 40)}${esc(S.me.name)}（あなた）</div>${r.members.map((id) => `<div class="item link" data-p="${esc(id)}"><span style="display:flex;gap:12px;align-items:center">${avatar(user(id), 40)}${esc(displayName(id))}</span></div>`).join("")}</div></div>`);
    back.querySelectorAll("[data-p]").forEach((el) => (el.onclick = () => { closeSheet(); openProfile(el.dataset.p); }));
  },
  editProfile() {
    const me = S.me;
    let icon_ = null, bg = null, removeIcon = false, removeBg = false;
    const back = sheetFrame("プロフィールを編集", `<div class="form">
      <div style="position:relative;height:220px">
        <div data-bg style="position:absolute;inset:0 0 40px 0;border-radius:20px;background:${backdropURL(me) ? `url('${esc(backdropURL(me))}') center/cover` : "var(--card)"};cursor:pointer"></div>
        <div data-icon style="position:absolute;left:50%;bottom:0;transform:translateX(-50%);border:3px solid #fff;border-radius:50%;cursor:pointer">${avatar(me, 96)}</div>
      </div>
      <div class="hint" style="text-align:center">タップで写真を選ぶ・長押しで外す</div>
      <div class="section-title">名前</div><div class="group"><label><input id="ename" type="text" maxlength="20" value="${esc(me.name)}"></label></div>
      <div class="section-title">Mybio</div><div class="group"><label><textarea id="ebio" maxlength="500">${esc(me.bio)}</textarea></label></div>
      <div class="group"><label>誕生日<input id="ebd" type="date" value="${me.birthday ? `${me.birthday.getFullYear()}-${pad(me.birthday.getMonth() + 1)}-${pad(me.birthday.getDate())}` : ""}"></label></div>
      <div class="group"><div class="item">toocID<span style="margin-left:auto;color:var(--text2)">@${esc(me.id)}</span></div></div>
      <input type="file" accept="image/*" hidden id="ficon"><input type="file" accept="image/*" hidden id="fbg"></div>`, { right: `<button class="btn" style="height:34px" data-save>保存</button>`, tall: true });
    const $bg = back.querySelector("[data-bg]"), $icon = back.querySelector("[data-icon]");
    $bg.onclick = () => back.querySelector("#fbg").click();
    $icon.onclick = () => back.querySelector("#ficon").click();
    longPress($bg, () => { removeBg = true; bg = null; $bg.style.background = "var(--card)"; });
    longPress($icon, () => { removeIcon = true; icon_ = null; $icon.innerHTML = avatar({ ...me, iconURL: null }, 96); });
    back.querySelector("#ficon").onchange = (e) => { icon_ = e.target.files[0]; removeIcon = false; if (icon_) $icon.innerHTML = `<div class="avatar" style="width:96px;height:96px"><img src="${URL.createObjectURL(icon_)}" alt=""></div>`; };
    back.querySelector("#fbg").onchange = (e) => { bg = e.target.files[0]; removeBg = false; if (bg) $bg.style.background = `url('${URL.createObjectURL(bg)}') center/cover`; };
    back.querySelector("[data-save]").onclick = async () => {
      const b = back.querySelector("[data-save]"); b.disabled = true;
      try {
        const bd = back.querySelector("#ebd").value;
        const fields = { name: back.querySelector("#ename").value.trim() || S.account, bio: back.querySelector("#ebio").value, updatedAt: Timestamp.now(),
          birthday: bd ? Timestamp.fromDate(new Date(`${bd}T00:00:00`)) : deleteField() };
        if (icon_) fields.iconURL = await uploadImage(new File([await shrink(icon_, 1024, true)], "i.jpg"), `users/${S.account}/icon`, 1024);
        else if (removeIcon) fields.iconURL = deleteField();
        if (bg) fields.backgroundURL = await uploadImage(bg, `users/${S.account}/background`, 2048);
        else if (removeBg) fields.backgroundURL = deleteField();
        await updateDoc(doc(S.fb.db, "users", S.account), fields);
        closeSheet();
      } catch (e) { toast(describe(e)); b.disabled = false; }
    };
  },
  groupEdit(s) {
    const r = roomView(S.rooms[s.roomID]);
    const members = new Set(r.members);
    const pool = [...new Set([...r.members, ...friends().map((u) => u.id)])];
    let icon_ = null, bg = null;
    const back = sheetFrame("グループプロフィール", `<div class="form">
      <div style="position:relative;height:220px"><div data-bg style="position:absolute;inset:0 0 40px 0;border-radius:20px;background:${r.backgroundURL ? `url('${esc(r.backgroundURL)}') center/cover` : "var(--card)"};cursor:pointer"></div>
      <div data-icon style="position:absolute;left:50%;bottom:0;transform:translateX(-50%);border:3px solid #fff;border-radius:50%;cursor:pointer">${avatar(iconUser(r), 96)}</div></div>
      <div class="section-title">グループ名</div><div class="group"><label><input id="gname" type="text" value="${esc(r.title || "")}"></label></div>
      <div class="section-title">メンバー</div><div class="group"><div class="item">${avatar(S.me, 36)}${esc(S.me.name)}（あなた）</div>${pool.map((id) => `<div class="item link" data-m="${esc(id)}"><span style="display:flex;gap:12px;align-items:center">${avatar(user(id), 36)}${esc(displayName(id))}</span><span data-mark style="color:${members.has(id) ? "var(--accent)" : "var(--text3)"}">${members.has(id) ? "●" : "○"}</span></div>`).join("")}</div>
      <input type="file" accept="image/*" hidden id="ficon"><input type="file" accept="image/*" hidden id="fbg"></div>`, { right: `<button class="btn" style="height:34px" data-save>保存</button>`, tall: true });
    back.querySelector("[data-bg]").onclick = () => back.querySelector("#fbg").click();
    back.querySelector("[data-icon]").onclick = () => back.querySelector("#ficon").click();
    back.querySelector("#ficon").onchange = (e) => { icon_ = e.target.files[0]; if (icon_) back.querySelector("[data-icon]").innerHTML = `<div class="avatar" style="width:96px;height:96px"><img src="${URL.createObjectURL(icon_)}" alt=""></div>`; };
    back.querySelector("#fbg").onchange = (e) => { bg = e.target.files[0]; if (bg) back.querySelector("[data-bg]").style.background = `url('${URL.createObjectURL(bg)}') center/cover`; };
    back.querySelectorAll("[data-m]").forEach((el) => (el.onclick = () => { const id = el.dataset.m; members.has(id) ? members.delete(id) : members.add(id); const mk = el.querySelector("[data-mark]"); mk.textContent = members.has(id) ? "●" : "○"; mk.style.color = members.has(id) ? "var(--accent)" : "var(--text3)"; }));
    back.querySelector("[data-save]").onclick = async () => {
      try {
        const list = [...members];
        const fields = { title: back.querySelector("#gname").value.trim() || r.title, members: [S.account, ...list], memberUIDs: [S.uid, ...list.map((x) => S.profiles[x]?.uid).filter(Boolean)], updatedAt: Timestamp.now() };
        if (icon_) fields.iconURL = await uploadImage(new File([await shrink(icon_, 1024, true)], "i.jpg"), `rooms/${r.id}/icon`, 1024);
        if (bg) fields.backgroundURL = await uploadImage(bg, `rooms/${r.id}/background`, 2048);
        await updateDoc(doc(S.fb.db, "rooms", r.id), fields);
        closeSheet();
      } catch (e) { toast(describe(e)); }
    };
  },
  accounts() {
    const list = saved.list;
    const back = sheetFrame("アカウント", `<div class="form"><div class="group">${list.map((a) => `<div class="item link" data-a="${esc(a.id)}"><span style="display:flex;gap:12px;align-items:center">${avatar(a.id === S.account ? S.me : a, 44)}<span><b>${esc(a.id === S.account ? S.me.name : a.name)}</b><br><small style="color:var(--text2)">@${esc(a.id)}</small></span></span>${a.id === S.account ? `<span style="color:var(--accent)">${icon("check")}</span>` : `<button class="icon-button" data-forget="${esc(a.id)}" aria-label="この端末から外す" style="color:var(--text2)">${icon("trash")}</button>`}</div>`).join("")}</div>
      <div class="group"><div class="item link" data-other style="color:var(--accent)">別のアカウントでログイン</div></div></div>`);
    back.querySelectorAll("[data-a]").forEach((el) => (el.onclick = (e) => { if (e.target.closest("[data-forget]")) return; closeSheet(); switchTo(el.dataset.a); }));
    back.querySelectorAll("[data-forget]").forEach((b) => (b.onclick = () => { saved.forget(b.dataset.forget); renderSheet(); }));
    back.querySelector("[data-other]").onclick = () => { closeSheet(); saved.previous = S.account; stop(); saved.current = null; render(); renderLogin("login"); };
  },
  fullText(s) { sheetFrame(s.title, `<div style="padding:20px;white-space:pre-wrap;font-size:var(--text-size);user-select:text">${linkify(esc(s.text))}</div>`, { tall: true }); },
  roomSearch(s) {
    const r = roomView(S.rooms[s.roomID]);
    const back = sheetFrame("トーク内を検索", `<div class="form"><div class="group"><label>${icon("search")}<input id="rq" type="search" placeholder="トーク内を検索"></label></div></div><div id="rr"></div>`, { tall: true });
    const input = back.querySelector("#rq");
    input.focus();
    input.oninput = () => {
      const q = input.value.trim().toLowerCase();
      const hits = q ? r.messages.filter((m) => m.kind.type === "text" && m.kind.text.toLowerCase().includes(q)).reverse() : [];
      back.querySelector("#rr").innerHTML = hits.map((m) => `<div class="row" style="height:auto;min-height:60px" data-hit="${m.id}">${avatar(user(m.senderID), 32)}<div><small style="color:var(--text2)">${listLabel(m.date)} ${clock(m.date)}</small><div>${esc(m.kind.text)}</div></div></div>`).join("");
      back.querySelectorAll("[data-hit]").forEach((el) => (el.onclick = () => {
        closeSheet();
        const target = $app.querySelector(`[data-msg="${el.dataset.hit}"]`);
        target?.scrollIntoView({ block: "center", behavior: "smooth" });
        target?.querySelector(".bubble")?.animate([{ boxShadow: "0 0 0 3px var(--accent)" }, { boxShadow: "0 0 0 0 transparent" }], { duration: 1600 });
      }));
    };
  },
  emoji(s) {
    const groups = [
      ["顔", [[0x1F600, 0x1F64F], [0x1F910, 0x1F92F], [0x1F970, 0x1F97A]]], ["手・人", [[0x1F440, 0x1F450], [0x1F466, 0x1F487], [0x1F90C, 0x1F90F]]],
      ["ハート・記号", [[0x1F493, 0x1F49F], [0x1F4A2, 0x1F4AF], [0x1F525, 0x1F525]]], ["動物・自然", [[0x1F400, 0x1F43F], [0x1F330, 0x1F344], [0x1F308, 0x1F31F]]],
      ["食べもの", [[0x1F345, 0x1F37F], [0x1F950, 0x1F96F]]], ["活動・もの", [[0x1F380, 0x1F3CA], [0x1F4B0, 0x1F4FF]]], ["乗りもの・場所", [[0x1F680, 0x1F6C5], [0x1F3E0, 0x1F3F0]]],
    ].map(([t, ranges]) => [t, (t === "ハート・記号" ? ["❤️", "🧡", "💛", "💚", "💙", "💜", "🤎", "🖤", "🤍"] : []).concat(ranges.flatMap(([a, b]) => Array.from({ length: b - a + 1 }, (_, i) => String.fromCodePoint(a + i))).filter((e) => /\p{Emoji_Presentation}/u.test(e)))]);
    let editing = false, slot = 0;
    const draw = () => {
      const favs = S.local.settings.favoriteReactions;
      const back = sheetFrame(editing ? "よく使う絵文字を入れ替え" : "リアクション", `<div class="section-title">${editing ? "入れ替える場所を選んで、下の絵文字をタップ" : "よく使う"}</div>
        <div class="favorite-slots">${favs.map((e, i) => `<button data-slot="${i}" class="${editing && slot === i ? "on" : ""}">${e}</button>`).join("")}</div>
        ${groups.map(([t, list]) => `<div class="section-title">${t}</div><div class="emoji-grid">${list.map((e) => `<button data-emoji="${e}">${e}</button>`).join("")}</div>`).join("")}`,
        { right: `<button style="color:var(--accent);font-weight:600" data-edit>${editing ? "完了" : "編集"}</button>`, tall: true });
      const pick = (e) => {
        if (editing) { const f = [...favs]; const ex = f.indexOf(e); if (ex >= 0) f[ex] = f[slot]; f[slot] = e; S.local.settings.favoriteReactions = f; saveLocal(); slot = (slot + 1) % 5; draw(); return; }
        const r = roomView(S.rooms[s.roomID]); const m = r.messages.find((x) => x.id === s.id);
        closeSheet(); if (m) react(r.id, m, e);
      };
      back.querySelector("[data-edit]").onclick = () => { editing = !editing; draw(); };
      back.querySelectorAll("[data-slot]").forEach((b) => (b.onclick = () => (editing ? ((slot = +b.dataset.slot), draw()) : pick(favs[+b.dataset.slot]))));
      back.querySelectorAll("[data-emoji]").forEach((b) => (b.onclick = () => pick(b.dataset.emoji)));
    };
    draw();
  },
  schedule(s) {
    const d = new Date(Date.now() + 3600000);
    const local = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
    const back = sheetFrame("時刻指定して送信", `<div class="form"><div class="group"><label>送信日時<input id="when" type="datetime-local" value="${local}"></label></div></div>`, { right: `<button class="btn" style="height:34px" data-ok>予約</button>` });
    back.querySelector("[data-ok]").onclick = () => {
      const at = new Date(back.querySelector("#when").value);
      if (!(at > now())) return toast("これからの日時を選んでください");
      closeSheet();
      submit(roomView(S.rooms[s.roomID]), { at });
    };
  },
  poll(s) {
    const back = sheetFrame("投票", `<div class="form"><div class="section-title">質問</div><div class="group"><label><input id="pq" type="text" placeholder="例：打ち上げどこにする？"></label></div>
      <div class="section-title">選択肢</div><div class="group" id="opts">${[1, 2].map((i) => `<label><input type="text" placeholder="選択肢${i}"></label>`).join("")}</div><button class="btn secondary" data-addopt>${icon("plus")}選択肢を追加</button>
      <div class="group"><label>複数選択できる<input class="toggle" type="checkbox" id="pm"></label>${deadlineFields()}</div></div>`, { right: `<button class="btn" style="height:34px" data-ok>送信</button>`, tall: true });
    bindDeadline(back);
    back.querySelector("[data-addopt]").onclick = () => { const g = back.querySelector("#opts"); if (g.children.length < 10) g.insertAdjacentHTML("beforeend", `<label><input type="text" placeholder="選択肢${g.children.length + 1}"></label>`); };
    back.querySelector("[data-ok]").onclick = () => {
      const question = back.querySelector("#pq").value.trim();
      const options = [...back.querySelectorAll("#opts input")].map((i) => i.value.trim()).filter(Boolean);
      if (!question || options.length < 2) return toast("質問と2つ以上の選択肢を入れてください");
      closeSheet();
      send(s.roomID, { type: "poll", question, options, multiple: back.querySelector("#pm").checked, deadline: readDeadline(back) });
    };
  },
  datePoll(s) {
    const dates = [];
    const back = sheetFrame("日程調整", `<div class="form"><div class="section-title">タイトル</div><div class="group"><label><input id="dt" type="text" placeholder="例：打ち上げ"></label></div>
      <div class="section-title">候補日</div><div class="group" id="dl"></div><div class="group"><label>候補<input id="dn" type="datetime-local"></label></div><button class="btn secondary" data-adddate>${icon("plus")}候補に追加</button>
      <div class="group">${deadlineFields()}</div></div>`, { right: `<button class="btn" style="height:34px" data-ok>送信</button>`, tall: true });
    bindDeadline(back);
    const drawList = () => (back.querySelector("#dl").innerHTML = dates.map((d, i) => `<div class="item">${candidate(d)}<button class="icon-button" style="margin-left:auto;color:var(--red)" data-rm="${i}">${icon("x")}</button></div>`).join("") || `<div class="item" style="color:var(--text2)">まだありません</div>`);
    drawList();
    back.querySelector("#dl").onclick = (e) => { const b = e.target.closest("[data-rm]"); if (b) { dates.splice(+b.dataset.rm, 1); drawList(); } };
    back.querySelector("[data-adddate]").onclick = () => { const v = back.querySelector("#dn").value; if (v) { dates.push(new Date(v)); dates.sort((a, b) => a - b); drawList(); } };
    back.querySelector("[data-ok]").onclick = () => {
      const title = back.querySelector("#dt").value.trim();
      if (!title || !dates.length) return toast("タイトルと候補日を入れてください");
      closeSheet();
      send(s.roomID, { type: "datePoll", title, dates, deadline: readDeadline(back) });
    };
  },
  "amida-new"(s) {
    const r = roomView(S.rooms[s.roomID]);
    const people = [S.me.name, ...r.members.map(displayName)];
    if (people.length < 2) people.push("");
    const back = sheetFrame("あみだくじ", `<div class="form"><div class="section-title">タイトル</div><div class="group"><label><input id="at" type="text" placeholder="例：買い出し係"></label></div>
      <div class="section-title">参加する人</div><div class="group" id="ae">${people.map((p, i) => `<label><input type="text" value="${esc(p)}" placeholder="参加者${i + 1}"></label>`).join("")}</div><button class="btn secondary" data-adde>${icon("plus")}参加者を追加</button>
      <div class="section-title">結果</div><div class="group" id="ap">${people.map((_, i) => `<label><input type="text" value="${i === 0 ? "当たり" : "はずれ"}" placeholder="結果${i + 1}"></label>`).join("")}</div>
      <div class="group">${deadlineFields()}</div></div>`, { right: `<button class="btn" style="height:34px" data-ok>送信</button>`, tall: true });
    bindDeadline(back);
    back.querySelector("[data-adde]").onclick = () => {
      const e = back.querySelector("#ae"); if (e.children.length >= 10) return;
      e.insertAdjacentHTML("beforeend", `<label><input type="text" placeholder="参加者${e.children.length + 1}"></label>`);
      back.querySelector("#ap").insertAdjacentHTML("beforeend", `<label><input type="text" value="はずれ"></label>`);
    };
    back.querySelector("[data-ok]").onclick = () => {
      const entrants = [...back.querySelectorAll("#ae input")].map((i) => i.value.trim());
      const prizes = [...back.querySelectorAll("#ap input")].map((i) => i.value.trim());
      if (entrants.length < 2 || entrants.some((x) => !x) || prizes.some((x) => !x)) return toast("参加者と結果をすべて入れてください");
      closeSheet();
      send(s.roomID, { type: "amida", title: back.querySelector("#at").value.trim() || "あみだくじ", entrants, prizes, rungs: makeRungs(entrants.length), deadline: readDeadline(back) });
    };
  },
  amida(s) {
    const r = roomView(S.rooms[s.roomID]);
    const m = r.messages.find((x) => x.id === s.id);
    if (!m) return;
    const a = m.kind;
    const n = a.entrants.length, colW = n > 5 ? 72 : Math.floor(Math.min(innerWidth, 560) / n) - 4, W = colW * n, H = 340;
    const xs = (c) => colW * (c + 0.5), ys = (l) => (H * (l + 1)) / 10;
    const color = (i) => `hsl(${(i / n) * 360} 65% 50%)`;
    const ladder = a.entrants.map((_, c) => `M${xs(c)} 0V${H}`).join("") + a.rungs.map((x) => `M${xs(x.column)} ${ys(x.level)}H${xs(x.column + 1)}`).join("");
    const paths = a.entrants.map((_, i) => { const w = amidaWalk(a, i); let d = `M${xs(w[0])} 0`; for (let l = 0; l < 9; l++) { d += `V${ys(l)}`; if (w[l + 1] !== w[l]) d += `H${xs(w[l + 1])}`; } return `${d}V${H}`; });
    const back = sheetFrame(a.title, `<div style="padding:16px;display:grid;gap:12px">
      <div class="amida"><div style="width:${W}px"><div style="display:flex">${a.entrants.map((e, i) => `<b style="width:${colW}px;text-align:center;font-size:12px;color:${color(i)}">${esc(e)}</b>`).join("")}</div>
      <svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><path d="${ladder}" stroke="var(--text3)" stroke-width="2" fill="none"/>${paths.map((d, i) => `<path d="${d}" stroke="${color(i)}" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round" pathLength="1" stroke-dasharray="1" stroke-dashoffset="${a.revealed ? 0 : 1}" class="walk"/>`).join("")}</svg>
      <div style="display:flex" id="prizes">${a.prizes.map((p) => `<b style="width:${colW}px;text-align:center;font-size:12px">${a.revealed ? esc(p) : "？"}</b>`).join("")}</div></div></div>
      <div id="results">${a.revealed ? resultsHTML() : `<button class="btn wide" data-start>スタート</button>`}</div></div>`, { tall: true });
    function resultsHTML() { return `<div class="box" style="padding:14px;display:grid;gap:6px">${a.entrants.map((e, i) => `<div style="display:flex;gap:8px;align-items:center"><span style="width:10px;height:10px;border-radius:50%;background:${color(i)}"></span><span style="flex:1">${esc(e)}</span><b>${esc(a.prizes[amidaWalk(a, i).at(-1)])}</b></div>`).join("")}</div>`; }
    back.querySelector("[data-start]")?.addEventListener("click", () => {
      back.querySelectorAll(".walk").forEach((p) => p.animate([{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], { duration: 2600, easing: "ease-in-out", fill: "forwards" }));
      setTimeout(() => {
        S.local.revealed.push(m.id); saveLocal();
        back.querySelector("#prizes").innerHTML = a.prizes.map((p) => `<b style="width:${colW}px;text-align:center;font-size:12px">${esc(p)}</b>`).join("");
        back.querySelector("#results").innerHTML = resultsHTML();
        const msg = S.messages[r.id]?.find((x) => x.id === m.id); if (msg) msg.kind.revealed = true;
        refresh();
      }, 2650);
    });
  },
};

const deadlineFields = () => `<label>期限<input class="toggle" type="checkbox" data-dl></label><label class="hidden" data-dlrow>締め切り<input type="datetime-local" data-dlv></label>`;
function bindDeadline(back) {
  const t = back.querySelector("[data-dl]"), row = back.querySelector("[data-dlrow]"), v = back.querySelector("[data-dlv]");
  const d = new Date(Date.now() + 2 * 86400000); d.setHours(23, 59, 0, 0);
  v.value = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T23:59`;
  t.onchange = () => row.classList.toggle("hidden", !t.checked);
}
const readDeadline = (back) => (back.querySelector("[data-dl]").checked ? new Date(back.querySelector("[data-dlv]").value) : null);

async function scanQR() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
    const back = sheetFrame("スキャン", `<video autoplay playsinline muted style="width:100%;max-height:70dvh;background:#000"></video>`, { tall: true });
    const video = back.querySelector("video");
    video.srcObject = stream;
    const detector = new BarcodeDetector({ formats: ["qr_code"] });
    const stopAll = () => stream.getTracks().forEach((t) => t.stop());
    back.querySelector("[data-x]").addEventListener("click", stopAll);
    const tick = async () => {
      if (!document.body.contains(video)) return stopAll();
      const codes = await detector.detect(video).catch(() => []);
      const text = codes[0]?.rawValue;
      const id = text?.match(/@([a-z0-9._]{4,20})/i)?.[1] || (REPLIES_OK.test(text || "") ? text : null);
      if (id) { stopAll(); openSheet({ type: "find", id: id.toLowerCase() }); return; }
      if (text) toast("toocのQRコードではありません");
      requestAnimationFrame(tick);
    };
    video.onloadeddata = tick;
  } catch { toast("カメラを使えません"); }
}

// ---------- banner

function renderBanner() {
  document.querySelector(".banner")?.remove();
  const n = S.banner;
  if (!n) return;
  const el = document.createElement("div");
  el.className = "banner glass";
  el.innerHTML = `${n.userID ? avatar(user(n.userID), 36) : `<span style="color:var(--accent)">${icon("bell")}</span>`}<div style="min-width:0"><b>${esc(n.title)}</b><span>${esc(S.local.settings.showContent ? n.body : "新しいお知らせがあります")}</span></div>`;
  el.onclick = () => { el.remove(); S.banner = null; if (n.roomID) openRoom(n.roomID); else if (n.userID) openProfile(n.userID); };
  document.body.append(el);
  setTimeout(() => { if (S.banner === n) { el.remove(); S.banner = null; } }, 3500);
}

// ---------------------------------------------------------------- start

async function boot() {
  render();
  if (!configured) return;
  const current = saved.current;
  if (current) {
    const fb = appFor(current);
    await fb.auth.authStateReady();
    if (fb.auth.currentUser) { start(current, fb); render(); return; }
    saved.current = null;
  }
  render();
}

document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && S.openRoom) markRead(S.openRoom); });
window.addEventListener("popstate", () => { if (S.view) closeView(); });
boot();
