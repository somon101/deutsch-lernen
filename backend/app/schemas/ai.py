from pydantic import BaseModel, Field


class AiSettingsUpdateInput(BaseModel):
    # "" removes the key; omitted leaves it unchanged.
    apiKey: str | None = Field(default=None, max_length=500)
    model: str | None = Field(default=None, max_length=100)
    # "" restores the built-in default; omitted leaves it unchanged.
    systemPrompt: str | None = Field(default=None, max_length=20000)


class AiPreviewInput(BaseModel):
    instructions: str | None = Field(default=None, max_length=2000)
    # Lessons already generated earlier in this same run (title + wordIds),
    # so the next one neither repeats a topic nor reuses the same words.
    previous: list[dict] = Field(default_factory=list, max_length=10)


class AiApplyInput(BaseModel):
    lessons: list[dict] = Field(min_length=1, max_length=10)
