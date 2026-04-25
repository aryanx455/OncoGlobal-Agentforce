import { LightningElement, track } from 'lwc';
import processMessage from '@salesforce/apex/AgentConversationController.processMessage';

const WELCOME = "Hi! I'm your OncoGlobal post-visit assistant. Tell me — where did you go today, what happened? I'll log it for you.";

const HINGLISH_MARKERS = [
    'gaya','gaye','mila','mili','nahi','nahin','karo','bolo','toh','hoon',
    'woh','yeh ','bhi ','phir','abhi','theek','dobara','kuch','chahiye',
    'hoga','liye','baad ','aaj','kharcha','sahab','milna','bhejna',
    'jaana','karein','sakte','aur ','mein ','pe ','se ',' ka ',' ki ',' ke '
];

export default class OncoVoiceAgent extends LightningElement {

    // ── State ──────────────────────────────────────────────────────────────────
    @track chatHistory   = [];
    @track isListening   = false;
    @track isThinking    = false;
    @track interimText   = '';
    @track typedText     = '';
    @track ttsEnabled    = true;
    @track statusLabel   = 'Ready';
    @track selectedLang  = 'english';  // English by default; auto-switches on Hinglish input

    sessionVisitReportId = '';
    sessionPhysicianName = '';

    recognition      = null;
    msgCounter       = 0;
    synth            = window.speechSynthesis;
    _lastInterimText = '';
    _isSubmitting    = false;         // prevents concurrent Apex calls

    // ── Lifecycle ──────────────────────────────────────────────────────────────
    connectedCallback() {
        this._pushAgentBubble(WELCOME);
        this._initSpeechRecognition();
    }

    disconnectedCallback() {
        if (this.recognition) this.recognition.abort();
        this.synth.cancel();
    }

    // ── Speech recognition ─────────────────────────────────────────────────────
    _initSpeechRecognition() {
        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) {
            console.warn('Speech recognition not supported — text mode only.');
            return;
        }
        this._buildRecognizer();
    }

    _buildRecognizer() {
        const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SpeechRecognition) return;

        if (this.recognition) {
            try { this.recognition.abort(); } catch(e) { /* ignore */ }
        }

        const rec = new SpeechRecognition();
        rec.continuous     = false;
        rec.interimResults = true;
        rec.lang           = this.selectedLang === 'english' ? 'en-US' : 'en-IN';

        rec.onstart = () => {
            this.isListening = true;
            this._lastInterimText = '';
            this.statusLabel = this.selectedLang === 'english'
                ? 'Listening (English)…' : 'Listening (Hinglish)…';
        };

        rec.onresult = (event) => {
            let interim = '';
            let final   = '';
            for (let i = event.resultIndex; i < event.results.length; i++) {
                const t = event.results[i][0].transcript;
                if (event.results[i].isFinal) {
                    final += t;
                } else {
                    interim += t;
                }
            }
            this.interimText = interim;
            if (interim) this._lastInterimText = interim;
            if (final) {
                const finalClean = final.trim();
                this.interimText      = '';
                this._lastInterimText = '';
                if (finalClean) this._submitTranscript(finalClean);
            }
        };

        // Fired when recognition stops — use interim fallback if no final came through
        rec.onend = () => {
            this.isListening = false;
            this.statusLabel = 'Ready';
            const fallback = (this._lastInterimText || '').trim();
            this._lastInterimText = '';
            this.interimText      = '';
            if (fallback) {
                this._submitTranscript(fallback);
            }
        };

        rec.onerror = (e) => {
            this.isListening     = false;
            this._lastInterimText = '';
            this.interimText      = '';
            this.statusLabel = e.error === 'not-allowed'
                ? 'Mic blocked — allow microphone access'
                : 'Mic error — try again';
            console.error('SpeechRecognition error', e.error);
        };

        this.recognition = rec;
    }

    // ── UI handlers ────────────────────────────────────────────────────────────
    handleMicToggle() {
        if (!this.recognition) {
            this._pushAgentBubble('Sorry, your browser does not support voice. Please type your message.');
            return;
        }
        if (this.isListening) {
            this.recognition.stop();
        } else {
            this.synth.cancel();
            this.recognition.start();
        }
    }

    handleTyping(evt) { this.typedText = evt.target.value; }

    handleKeyDown(evt) {
        if (evt.key === 'Enter' && this.typedText.trim()) this.handleSend();
    }

    handleSend() {
        const text = this.typedText.trim();
        if (!text) return;
        this.typedText = '';
        this._submitTranscript(text);
    }

    handleTtsToggle(evt) {
        this.ttsEnabled = evt.target.checked;
        if (!this.ttsEnabled) this.synth.cancel();
    }

    setLangHinglish() {
        this.selectedLang = 'hinglish';
        this._buildRecognizer();
    }

    setLangEnglish() {
        this.selectedLang = 'english';
        this._buildRecognizer();
    }

    handleClear() {
        this.synth.cancel();
        this.sessionVisitReportId = '';
        this.sessionPhysicianName = '';
        this.chatHistory = [];
        this._pushAgentBubble(WELCOME);
    }

    // ── Language auto-detection ────────────────────────────────────────────────
    _detectAndSwitchLang(text) {
        if (this.selectedLang === 'hinglish') return; // already switched, stay
        const lower = ' ' + text.toLowerCase() + ' ';
        const isHinglish = HINGLISH_MARKERS.some(m => lower.includes(m));
        if (isHinglish) {
            this.selectedLang = 'hinglish';
            this._buildRecognizer(); // switch mic to en-IN for future utterances
        }
    }

    // ── Core: send transcript → Apex → response ────────────────────────────────
    async _submitTranscript(transcript) {
        if (!transcript || !transcript.trim()) return;
        if (this._isSubmitting) return;
        this._detectAndSwitchLang(transcript);
        this._isSubmitting = true;
        this._pushUserBubble(transcript);
        this.isThinking = true;
        this.statusLabel = 'Thinking…';
        this._scrollToBottom();

        try {
            const result = await processMessage({
                req: {
                    transcript,
                    sessionVisitReportId: this.sessionVisitReportId,
                    sessionPhysicianName: this.sessionPhysicianName,
                    language: this.selectedLang
                }
            });

            if (result.visitReportId)  this.sessionVisitReportId = result.visitReportId;
            if (result.physicianName)  this.sessionPhysicianName = result.physicianName;

            this._pushAgentBubble(result.message);
            if (this.ttsEnabled) this._speak(result.message);

        } catch (err) {
            const msg = 'Kuch issue aaya. Dobara try karein.';
            this._pushAgentBubble(msg);
            console.error(err);
        } finally {
            this._isSubmitting = false;
            this.isThinking    = false;
            this.statusLabel   = 'Ready';
            this._scrollToBottom();
        }
    }

    // ── TTS ────────────────────────────────────────────────────────────────────
    _speak(text) {
        if (!this.synth) return;
        this.synth.cancel();
        // Strip emojis for cleaner audio
        const clean = text.replace(/[\u{1F300}-\u{1FAD6}]/gu, '').trim();
        const utt = new SpeechSynthesisUtterance(clean);
        utt.lang  = 'hi-IN';
        utt.rate  = 0.95;
        utt.pitch = 1.05;
        this.synth.speak(utt);
    }

    // ── Chat history helpers ───────────────────────────────────────────────────
    _pushUserBubble(text) {
        this.chatHistory = [...this.chatHistory, {
            id:         ++this.msgCounter,
            text,
            time:       this._now(),
            wrapClass:  'msg-wrap user-wrap',
            bubbleClass:'bubble user-bubble'
        }];
    }

    _pushAgentBubble(text) {
        this.chatHistory = [...this.chatHistory, {
            id:         ++this.msgCounter,
            text,
            time:       this._now(),
            wrapClass:  'msg-wrap agent-wrap',
            bubbleClass:'bubble agent-bubble'
        }];
    }

    _now() {
        return new Date().toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });
    }

    _scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const area = this.refs.chatArea;
            if (area) area.scrollTop = area.scrollHeight;
        }, 50);
    }

    // ── Computed props ─────────────────────────────────────────────────────────
    get micButtonClass() {
        return this.isListening ? 'btn-mic btn-mic--active' : 'btn-mic';
    }

    get micTitle() {
        return this.isListening ? 'Stop listening' : 'Tap to speak';
    }

    get isSendDisabled() {
        return this.isThinking || (!this.typedText.trim() && !this.isListening);
    }

    get langTabHinglish() {
        return this.selectedLang === 'hinglish' ? 'lang-tab lang-tab--active' : 'lang-tab';
    }

    get langTabEnglish() {
        return this.selectedLang === 'english' ? 'lang-tab lang-tab--active' : 'lang-tab';
    }
}
