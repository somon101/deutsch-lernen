from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import require_staff
from app.db import get_db
from app.errors import ApiError
from app.schemas.lesson_graph import CreateEdgeInput, CreateNodeInput, NodeMediaReuseInput, UpdateNodeInput
from app.services import courses as courses_svc
from app.services import lesson_graph as svc
from app.uploads.storage import COURSE_MEDIA_DIR, delete_file, save_course_media

router = APIRouter(prefix="/api/builder", tags=["lesson-graph"], dependencies=[Depends(require_staff)])


@router.get("/courses/{course_id}/lessons/{lesson_id}/graph")
async def get_graph(course_id: str, lesson_id: str, db: AsyncSession = Depends(get_db)):
    return await svc.get_lesson_graph(db, course_id, lesson_id)


@router.post("/courses/{course_id}/lessons/{lesson_id}/graph/materialize", status_code=201)
async def materialize_graph(course_id: str, lesson_id: str, db: AsyncSession = Depends(get_db)):
    return await svc.materialize_lesson_graph(db, course_id, lesson_id)


@router.post("/courses/{course_id}/lessons/{lesson_id}/graph/nodes", status_code=201)
async def create_node(course_id: str, lesson_id: str, body: CreateNodeInput, db: AsyncSession = Depends(get_db)):
    return {"node": await svc.create_node(db, course_id, lesson_id, body.type, body.title, body.posX, body.posY)}


@router.patch("/courses/{course_id}/lessons/{lesson_id}/graph/nodes/{node_id}")
async def update_node(course_id: str, lesson_id: str, node_id: str, body: UpdateNodeInput, db: AsyncSession = Depends(get_db)):
    return {"node": await svc.update_node(db, lesson_id, node_id, body.model_dump(exclude_unset=True))}


@router.post("/courses/{course_id}/lessons/{lesson_id}/graph/nodes/{node_id}/media")
async def upload_node_media(course_id: str, lesson_id: str, node_id: str, file: UploadFile = File(...), db: AsyncSession = Depends(get_db)):
    stored_url = await save_course_media(file)
    try:
        result = await svc.set_node_media(db, lesson_id, node_id, stored_url)
    except ApiError:
        delete_file(COURSE_MEDIA_DIR, stored_url)
        raise
    # Node media is never shared across nodes (unlike the legacy per-lesson
    # media library) — a node's previous file is always safe to delete.
    if result["previousMediaUrl"]:
        delete_file(COURSE_MEDIA_DIR, result["previousMediaUrl"])
    return {"node": result["node"]}


@router.delete("/courses/{course_id}/lessons/{lesson_id}/graph/nodes/{node_id}/media")
async def remove_node_media(course_id: str, lesson_id: str, node_id: str, db: AsyncSession = Depends(get_db)):
    result = await svc.set_node_media(db, lesson_id, node_id, None)
    if result["previousMediaUrl"]:
        delete_file(COURSE_MEDIA_DIR, result["previousMediaUrl"])
    return {"node": result["node"]}


@router.put("/courses/{course_id}/lessons/{lesson_id}/graph/nodes/{node_id}/media/reuse")
async def reuse_node_media(course_id: str, lesson_id: str, node_id: str, body: NodeMediaReuseInput, db: AsyncSession = Depends(get_db)):
    node_for_kind = await svc.get_node(db, lesson_id, node_id)
    library = await courses_svc.list_media_library(db, node_for_kind.type)
    if not any(entry["url"] == body.url for entry in library):
        raise ApiError(400, "Файл не найден в библиотеке")
    result = await svc.set_node_media(db, lesson_id, node_id, body.url)
    return {"node": result["node"]}


@router.delete("/courses/{course_id}/lessons/{lesson_id}/graph/nodes/{node_id}")
async def delete_node(course_id: str, lesson_id: str, node_id: str, db: AsyncSession = Depends(get_db)):
    removed_media_url = await svc.delete_node(db, course_id, lesson_id, node_id)
    if removed_media_url:
        delete_file(COURSE_MEDIA_DIR, removed_media_url)
    return {"ok": True}


@router.post("/courses/{course_id}/lessons/{lesson_id}/graph/edges", status_code=201)
async def add_edge(course_id: str, lesson_id: str, body: CreateEdgeInput, db: AsyncSession = Depends(get_db)):
    return {"edge": await svc.add_edge(db, course_id, lesson_id, body.fromNodeId, body.toNodeId)}


@router.delete("/courses/{course_id}/lessons/{lesson_id}/graph/edges/{edge_id}")
async def delete_edge(course_id: str, lesson_id: str, edge_id: str, db: AsyncSession = Depends(get_db)):
    ok = await svc.delete_edge(db, lesson_id, edge_id)
    if not ok:
        raise ApiError(404, "Связь не найдена")
    return {"ok": True}
