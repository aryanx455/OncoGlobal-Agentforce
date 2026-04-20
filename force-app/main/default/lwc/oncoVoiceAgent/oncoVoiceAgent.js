import { LightningElement, track } from 'lwc';
import processMessage from '@salesforce/apex/AgentConversationController.processMessage';

const WELCOME = 'Hi! Main hoon aapka OncoGlobal assistant. Bolo — aaj kahan gaye, kya hua? Main log kar deta hoon. 😊';

export default class OncoVoiceAgent extends LightningElement {

    // ── State ──────────────────────────────────────────────────────────────────
    @track chatHistory  = [];
    @track isListening  = false;
    @track isThinking   = false;
    @track interimText  = '';
    @track typedText    = '';
    @track ttsEnabled   = true;
    @track statusLabel  = 'Ready';

    sessionVisitReportId = '';
    sessionPhysicianName = '';

    recognition   = null;
    msgCounter    = 0;
    synth         = window.speechSynthesis;

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
        const rec = new SpeechRecognition();
        rec.continuous      = false;
        rec.interimResults  = true;
        rec.lang            = 'hi-IN';      // Hinglish-friendly; falls back to English words

        rec.onstart  = () => { this.isListening = true; this.statusLabel = 'Listening…'; };
        rec.onend    = () => { this.isListening = false; this.interimText = ''; this.statusLabel = 'Ready'; };
        rec.onerror  = (e) => { this.isListening = false; this.statusLabel = 'Mic error — try again'; console.error(e); };

        rec.onresult = (event) => {
            let interim = '';
            let final   = '';
            for (let i = event.resultIndex; i < event.results.length; i++) {
                const t = event.results[i][0].transcript;
                if (event.results[i].isFinal) final += t;
                else interim += t;
            }
            this.interimText = interim;
            if (final) {
                this.interimText = '';
                this._submitTranscript(final.trim());
            }
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

    handleClear() {
        this.synth.cancel();
        this.sessionVisitReportId = '';
        this.sessionPhysicianName = '';
        this.chatHistory = [];
        this._pushAgentBubble(WELCOME);
    }

    // ── Core: send transcript → Apex → response ────────────────────────────────
    async _submitTranscript(transcript) {
        this._pushUserBubble(transcript);
        this.isThinking = true;
        this.statusLabel = 'Thinking…';
        this._scrollToBottom();

        try {
            const result = await processMessage({
                req: {
                    transcript,
                    sessionVisitReportId: this.sessionVisitReportId,
                    sessionPhysicianName: this.sessionPhysicianName
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
            this.isThinking  = false;
            this.statusLabel = 'Ready';
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
}
