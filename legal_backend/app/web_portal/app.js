'use strict';

(function () {
  const TOKEN_KEY = 'jarvis_chairman_session_tab';
  const $ = (id) => document.getElementById(id);
  const login = $('login-panel');
  const dashboard = $('chairman-panel');
  const sendButton = $('send-email');
  const verifyButton = $('verify');
  const verifyForm = $('verify-form');
  const status = $('status');
  const proof = $('proof');
  const ask = $('ask');
  const answer = $('answer');
  let busy = false;

  function setStatus(message, error) {
    status.textContent = message;
    status.className = error ? 'status error' : 'status';
  }

  function setBusy(value) {
    busy = value;
    sendButton.disabled = value;
    verifyButton.disabled = value;
  }

  async function api(path, options) {
    const response = await fetch(path, Object.assign({
      cache: 'no-store',
      credentials: 'omit',
      headers: { 'Content-Type': 'application/json' }
    }, options || {}));
    let body = {};
    try {
      body = await response.json();
    } catch (error) {
      body = {};
    }
    return { response, body };
  }

  async function showDashboard(token) {
    const result = await api('/v1/auth/session', {
      headers: { Authorization: 'Bearer ' + token }
    });
    if (!result.response.ok || !result.body.authenticated) {
      sessionStorage.removeItem(TOKEN_KEY);
      login.hidden = false;
      dashboard.hidden = true;
      setStatus('Your previous session expired. Request a new verification email.', true);
      return;
    }
    login.hidden = true;
    dashboard.hidden = false;
    $('session-email').textContent = 'Verified: ' + result.body.email;
    try {
      const health = await api('/health', { headers: {} });
      $('service-status').textContent = health.response.ok
        ? (health.body.ai_configured
          ? 'JARVIS cloud is online and the AI service is configured.'
          : 'Chairman identity verified. Cloud backend is online; AI configuration may still be required.')
        : 'Chairman identity verified. JARVIS health check was unavailable.';
    } catch (error) {
      $('service-status').textContent = 'Chairman identity verified. JARVIS health check was unavailable.';
    }
  }

  sendButton.addEventListener('click', async () => {
    if (busy) return;
    setBusy(true);
    setStatus('Requesting a secure verification email…', false);
    try {
      const result = await api('/v1/auth/email/start', {
        method: 'POST',
        body: '{}'
      });
      if (result.response.ok) {
        verifyForm.hidden = false;
        sendButton.textContent = 'RESEND VERIFICATION EMAIL';
        setStatus('Verification requested. Check your approved Chairman inbox and Spam folder. Do not share the code or link with anyone.', false);
      } else if (result.response.status === 429) {
        setStatus('Too many requests. Wait before requesting another email.', true);
      } else {
        setStatus('Verification is temporarily unavailable. Please try again later.', true);
      }
    } catch (error) {
      setStatus('Cannot reach JARVIS cloud right now. Check your connection and try again.', true);
    } finally {
      setBusy(false);
    }
  });

  verifyForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    const challenge = proof.value.trim();
    if (challenge.length < 6) {
      setStatus('Paste the code or full unused sign-in link from your email.', true);
      return;
    }
    setBusy(true);
    setStatus('Verifying your secure sign-in…', false);
    try {
      const result = await api('/v1/auth/email/verify', {
        method: 'POST',
        body: JSON.stringify({ proof: challenge })
      });
      if (!result.response.ok || !result.body.access_token) {
        const message = result.response.status === 429
          ? 'Too many attempts. Please wait before trying again.'
          : 'Invalid or expired code or link. Request another verification email.';
        setStatus(message, true);
        return;
      }
      proof.value = '';
      const token = String(result.body.access_token);
      sessionStorage.setItem(TOKEN_KEY, token);
      await showDashboard(token);
    } catch (error) {
      setStatus('Verification did not complete. Check your connection and try again.', true);
    } finally {
      setBusy(false);
    }
  });

  $('ask-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy) return;
    const token = sessionStorage.getItem(TOKEN_KEY);
    if (!token) {
      login.hidden = false;
      dashboard.hidden = true;
      setStatus('Your session has expired. Sign in again.', true);
      return;
    }
    const question = $('question').value.trim();
    if (!question) return;
    busy = true;
    ask.disabled = true;
    answer.textContent = 'Processing your command…';
    try {
      const result = await api('/v1/frontier/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
        body: JSON.stringify({ prompt: question, mode: 'reason' })
      });
      if (result.response.ok) {
        answer.textContent = String(result.body.answer || result.body.output || 'JARVIS returned no answer.');
      } else if (result.response.status === 401) {
        sessionStorage.removeItem(TOKEN_KEY);
        login.hidden = false;
        dashboard.hidden = true;
        setStatus('Session expired. Request a fresh verification email.', true);
      } else if (result.response.status === 503) {
        answer.textContent = 'You are securely signed in. The remote AI service needs to be configured on the backend.';
      } else {
        answer.textContent = 'JARVIS cloud could not complete that request. Try again.';
      }
    } catch (error) {
      answer.textContent = 'The JARVIS cloud request could not connect. Check your network and retry.';
    } finally {
      busy = false;
      ask.disabled = false;
    }
  });

  $('sign-out').addEventListener('click', () => {
    sessionStorage.removeItem(TOKEN_KEY);
    proof.value = '';
    dashboard.hidden = true;
    login.hidden = false;
    setStatus('Signed out on this browser tab.', false);
  });

  const existing = sessionStorage.getItem(TOKEN_KEY);
  if (existing) {
    showDashboard(existing).catch(() => {
      sessionStorage.removeItem(TOKEN_KEY);
      login.hidden = false;
      dashboard.hidden = true;
      setStatus('Could not restore your session. Request a fresh verification email.', true);
    });
  }
})();
