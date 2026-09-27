(() => {
	const touch = navigator.maxTouchPoints > 0 || 'ontouchstart' in window;
	const deviceSide = Math.max(screen.width || 0, screen.height || 0);
	const isMobile = touch && (deviceSide <= 1600 || /iPhone|iPad|iPod|Android/i.test(navigator.userAgent));
	const shell = document.getElementById('game-shell');
	const entry = document.getElementById('mobile-text-entry');
	const form = document.getElementById('mobile-text-form');
	const label = document.getElementById('mobile-text-label');
	const input = document.getElementById('mobile-text-input');
	const portraitQuery = window.matchMedia('(orientation: portrait)');
	let landscapeSize = null;
	let activeField = '';
	const results = [];
	let keyboardWasVisible = false;

	const isPortrait = () => {
		if (screen.orientation?.type) return screen.orientation.type.startsWith('portrait');
		if (typeof window.orientation === 'number') return Math.abs(window.orientation) < 45 || Math.abs(window.orientation) > 135;
		return portraitQuery.matches;
	};

	const positionEntry = () => {
		if (!activeField) return;
		const viewport = window.visualViewport;
		const left = viewport?.offsetLeft ?? 0;
		const top = viewport?.offsetTop ?? 0;
		const width = viewport?.width ?? window.innerWidth;
		entry.style.left = `${left + 8}px`;
		entry.style.top = `${top + 8}px`;
		entry.style.width = `${Math.max(width - 16, 240)}px`;
	};

	const updateGameViewport = () => {
		const portrait = isMobile && isPortrait();
		document.documentElement.classList.toggle('phone-portrait', portrait);
		if (!isMobile || !shell) return;
		if (portrait) {
			landscapeSize = null;
			for (const property of ['position', 'left', 'top', 'width', 'height']) shell.style.removeProperty(property);
			return;
		}
		const viewport = window.visualViewport;
		const width = viewport?.width ?? window.innerWidth;
		const height = viewport?.height ?? window.innerHeight;
		if (activeField && landscapeSize && height < landscapeSize.height * 0.75) keyboardWasVisible = true;
		if (!landscapeSize || (Math.abs(width - landscapeSize.width) > 80 && !activeField && height >= landscapeSize.height * 0.7)) {
			landscapeSize = { width, height };
		} else {
			if (!activeField && height >= landscapeSize.height * 0.7) landscapeSize.width = width;
			// The keyboard may reduce the visual viewport. Never feed that smaller
			// height back into the Godot iframe, even after the keyboard closes.
			landscapeSize.height = Math.max(landscapeSize.height, height);
		}
		shell.style.position = 'fixed';
		shell.style.left = '0px';
		shell.style.top = '0px';
		shell.style.width = `${landscapeSize.width}px`;
		shell.style.height = `${landscapeSize.height}px`;
		positionEntry();
	};

	const finish = (save) => {
		if (!activeField) return;
		if (save) results.push(JSON.stringify({ field: activeField, value: input.value }));
		activeField = '';
		keyboardWasVisible = false;
		entry.hidden = true;
		input.blur();
		window.scrollTo(0, 0);
		updateGameViewport();
	};

	window.GravityRunMobileInput = {
		isMobile,
		open(request) {
			if (!isMobile || !request || !['name', 'room_code'].includes(request.field)) return false;
			activeField = request.field;
			keyboardWasVisible = false;
			label.textContent = request.field === 'name' ? 'Spelarnamn' : 'Rumskod';
			input.value = String(request.value ?? '');
			input.maxLength = request.field === 'name' ? 16 : 8;
			input.autocapitalize = request.field === 'name' ? 'words' : 'characters';
			entry.hidden = false;
			positionEntry();
			input.focus({ preventScroll: true });
			input.select();
			return true;
		},
		takeResult() {
			return results.shift() ?? '';
		},
		cancel() { finish(false); },
	};

	form.addEventListener('submit', (event) => {
		event.preventDefault();
		finish(true);
	});
	input.addEventListener('blur', () => {
		// iOS "Klar" can dismiss the keyboard without submitting the form.
		setTimeout(() => finish(true), 0);
	});
	input.addEventListener('keydown', (event) => {
		if (event.key === 'Escape') finish(false);
	});
	window.visualViewport?.addEventListener?.('resize', () => {
		if (activeField && keyboardWasVisible && landscapeSize && window.visualViewport.height >= landscapeSize.height * 0.85) {
			finish(true);
		}
	});
	window.addEventListener('resize', updateGameViewport);
	window.addEventListener('orientationchange', updateGameViewport);
	screen.orientation?.addEventListener?.('change', updateGameViewport);
	portraitQuery.addEventListener?.('change', updateGameViewport);
	window.visualViewport?.addEventListener?.('resize', updateGameViewport);
	window.visualViewport?.addEventListener?.('scroll', positionEntry);
	updateGameViewport();
})();
