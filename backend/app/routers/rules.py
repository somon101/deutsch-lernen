from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_staff
from app.db import get_db
from app.errors import ApiError
from app.schemas.rule import RuleImportPayload, RuleInput, RuleUpdateInput
from app.services import rules as svc

router = APIRouter(prefix="/api/builder/rules", tags=["rules"], dependencies=[Depends(require_staff)])


@router.get("")
async def list_rules(languageId: str | None = None, q: str | None = None, limit: int = 50, offset: int = 0, db: AsyncSession = Depends(get_db)):
    return await svc.list_rules(db, language_id=languageId, query=q, limit=max(1, min(limit, 200)), offset=max(0, offset))


@router.post("", status_code=201)
async def create_rule(body: RuleInput, db: AsyncSession = Depends(get_db)):
    return {"rule": await svc.create_rule(db, language_id=body.languageId, text=body.text)}


@router.patch("/{rule_id}")
async def update_rule(rule_id: str, body: RuleUpdateInput, db: AsyncSession = Depends(get_db)):
    rule = await svc.update_rule(db, rule_id, body.text)
    if not rule:
        raise ApiError(404, "Правило не найдено")
    return {"rule": rule}


@router.delete("/{rule_id}")
async def delete_rule(rule_id: str, db: AsyncSession = Depends(get_db)):
    if not await svc.delete_rule(db, rule_id):
        raise ApiError(404, "Правило не найдено")
    return {"ok": True}


@router.post("/import")
async def import_rules(body: RuleImportPayload, db: AsyncSession = Depends(get_db)):
    return await svc.import_rules(db, body.languageId, [r.text for r in body.rules])
