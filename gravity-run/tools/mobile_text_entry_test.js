const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function element() {
	const listeners = {};
	return {
		style: { removeProperty(key) { delete this[key]; } },
		hidden: true,
		value: '',
		listeners,
		addEventListener(name, callback) { listeners[name] = callback; },
		focus() { this.focused = true; },
		select() {},
		blur() { this.focused = false; listeners.blur?.(); },
	};
}

const nodes = new Map(['game-shell', 'mobile-text-entry', 'mobile-text-form', 'mobile-text-label', 'mobile-text-input'].map((id) => [id, element()]));
const events = {};
const viewportEvents = {};
const viewport = {
	width: 1280,
	height: 510,
	offsetLeft: 0,
	offsetTop: 0,
	addEventListener(name, callback) { (viewportEvents[name] ??= []).push(callback); },
};
const window = {
	visualViewport: viewport,
	innerWidth: 1280,
	innerHeight: 510,
	addEventListener(name, callback) { events[name] = callback; },
	matchMedia() { return { matches: false, addEventListener() {} }; },
	scrollTo() {},
};
const document = {
	documentElement: { classList: { toggle() {} } },
	getElementById(id) { return nodes.get(id); },
};
const screen = { width: 1280, height: 590, orientation: { type: 'landscape-primary', addEventListener() {} } };
const source = fs.readFileSync(path.join(__dirname, '../web/mobile_text_entry.js'), 'utf8');
vm.runInNewContext(source, { window, document, screen, navigator: { maxTouchPoints: 5, userAgent: 'iPhone' }, setTimeout: (fn) => fn() });

const shell = nodes.get('game-shell');
const input = nodes.get('mobile-text-input');
const form = nodes.get('mobile-text-form');
assert.equal(shell.style.height, '510px');
assert.equal(window.GravityRunMobileInput.open({ field: 'name', value: 'Ada' }), true);
assert.equal(input.focused, true);
viewport.height = 160;
for (const callback of viewportEvents.resize) callback();
assert.equal(shell.style.height, '510px', 'opening the keyboard must not shrink the game');
input.value = 'Ada Lovelace';
form.listeners.submit({ preventDefault() {} });
assert.equal(shell.style.height, '510px', 'submitting with the keyboard open must retain game size');
assert.equal(JSON.parse(window.GravityRunMobileInput.takeResult()).value, 'Ada Lovelace');
viewport.height = 510;
for (const callback of viewportEvents.resize) callback();
assert.equal(shell.style.height, '510px', 'closing the keyboard must restore the original game size');
assert.equal(window.GravityRunMobileInput.takeResult(), '');

assert.equal(window.GravityRunMobileInput.open({ field: 'room_code', value: '' }), true);
viewport.height = 160;
for (const callback of viewportEvents.resize) callback();
input.value = 'ABC12345';
viewport.height = 510;
for (const callback of viewportEvents.resize) callback();
assert.equal(JSON.parse(window.GravityRunMobileInput.takeResult()).value, 'ABC12345', 'keyboard dismissal must preserve the typed value');
assert.equal(shell.style.height, '510px');
console.log('Mobile text entry viewport test passed.');
