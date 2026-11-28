import os
import tempfile
from pathlib import Path
from fastapi import FastAPI, File, Form, UploadFile
from faster_whisper import WhisperModel

app = FastAPI()
model = WhisperModel(os.getenv("WHISPER_MODEL", "small"), device=os.getenv("WHISPER_DEVICE", "cpu"), compute_type=os.getenv("WHISPER_COMPUTE_TYPE", "int8"))

@app.get("/health")
def health():
    return {"ok": True, "provider": "faster-whisper", "model": os.getenv("WHISPER_MODEL", "small")}

@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...), language: str = Form("es"), speaker_mode: str = Form("single"), speaker_count: int = Form(1)):
    suffix = Path(file.filename or "audio.m4a").suffix or ".m4a"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        filename = tmp.name
    try:
        # Voice notes can contain low-volume speech or pauses; OpenClaw's
        # media path must not discard the whole attachment during preflight.
        requested_language = (language or "es").split("-")[0].lower()
        language_arg = None if requested_language in {"auto", "detect", ""} else requested_language
        segments, info = model.transcribe(
            filename,
            language=language_arg,
            task="transcribe",
            beam_size=5,
            best_of=5,
            temperature=0.0,
            condition_on_previous_text=False,
            vad_filter=True,
            vad_parameters={
                "threshold": 0.35,
                "min_speech_duration_ms": 100,
                "min_silence_duration_ms": 500,
                "speech_pad_ms": 400,
            },
            word_timestamps=True,
            chunk_length=30,
            no_speech_threshold=0.6,
            log_prob_threshold=-1.0,
            compression_ratio_threshold=2.4,
            initial_prompt="Transcripción clara en español. Conserva nombres propios, números, términos técnicos y frases completas.",
        )
        rows = []
        for segment in segments:
            text = segment.text.strip()
            if not text:
                continue
            words = []
            for word in segment.words or []:
                words.append({"start": word.start, "end": word.end, "word": word.word.strip(), "probability": word.probability})
            confidence = sum(word["probability"] for word in words) / len(words) if words else 0.75
            rows.append({"start": segment.start, "end": segment.end, "text": text, "words": words, "confidence": confidence, "kind": "speech" if confidence >= 0.45 else "uncertain", "speaker": "Orador principal" if speaker_mode != "multi" else None})
        return {"text": " ".join(row["text"] for row in rows).strip(), "segments": rows, "language": info.language, "language_probability": info.language_probability, "duration": info.duration, "speaker_mode": speaker_mode if speaker_mode == "multi" else "single", "speaker_count": max(1, min(12, speaker_count)), "speaker_detection": "unavailable" if speaker_mode == "multi" else "single-speaker"}
    finally:
        try: os.unlink(filename)
        except OSError: pass
