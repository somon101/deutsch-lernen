from pydantic import BaseModel, Field, field_validator


class VocabularyWordInput(BaseModel):
    """Every field required — unlike content.ts's vocabularyItemSchema (used
    for the legacy bulk-save path), the builder's per-word form always
    collects all three."""

    german: str = Field(min_length=1)
    translation: str = Field(min_length=1)
    pronunciation: str = Field(min_length=1)

    @field_validator("german")
    @classmethod
    def _german(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Слово не может быть пустым")
        return v

    @field_validator("translation")
    @classmethod
    def _translation(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Перевод не может быть пустым")
        return v

    @field_validator("pronunciation")
    @classmethod
    def _pronunciation(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Транскрипция не может быть пустой")
        return v


class VocabularyWordUpdateInput(BaseModel):
    german: str | None = None
    translation: str | None = None
    pronunciation: str | None = None

    @field_validator("german", "translation", "pronunciation")
    @classmethod
    def _trim(cls, v: str | None) -> str | None:
        return v.strip() if v is not None else v


class VocabularyImportWordInput(BaseModel):
    original: str = Field(min_length=1)
    transcription: str = Field(min_length=1)
    translation: str = Field(min_length=1)

    @field_validator("original")
    @classmethod
    def _original(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Поле original не может быть пустым")
        return v

    @field_validator("transcription")
    @classmethod
    def _transcription(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Поле transcription не может быть пустым")
        return v

    @field_validator("translation")
    @classmethod
    def _translation(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Поле translation не может быть пустым")
        return v


class VocabularyImportPayload(BaseModel):
    words: list[VocabularyImportWordInput] = Field(min_length=1)
