from pydantic import BaseModel, Field


class PhraseInput(BaseModel):
    languageId: str
    text: str = Field(min_length=1, max_length=500)
    translation: str = Field(default="", max_length=1000)
    translations: dict[str, str] | None = None
    topicId: str | None = None


class PhraseUpdateInput(BaseModel):
    text: str | None = Field(default=None, max_length=500)
    translation: str | None = Field(default=None, max_length=1000)
    translations: dict[str, str] | None = None
    topicId: str | None = None


class PhraseImportItem(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    translation: str = Field(default="", max_length=1000)
    translation_tg: str | None = Field(default=None, max_length=1000)
    topic: str | None = Field(default=None, max_length=100)


class PhraseImportPayload(BaseModel):
    languageId: str
    phrases: list[PhraseImportItem] = Field(min_length=1, max_length=5000)
