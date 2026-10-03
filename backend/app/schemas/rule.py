from pydantic import BaseModel, ConfigDict, Field


class RuleInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    languageId: str
    text: str = Field(min_length=1, max_length=2000)


class RuleUpdateInput(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    text: str = Field(min_length=1, max_length=2000)


class RuleImportItem(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    text: str = Field(min_length=1, max_length=2000)


class RuleImportPayload(BaseModel):
    languageId: str
    rules: list[RuleImportItem] = Field(min_length=1, max_length=5000)
