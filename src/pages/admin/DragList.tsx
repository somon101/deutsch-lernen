import { ReactNode } from "react";
import {
  DndContext,
  DragEndEvent,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";

/**
 * Generic drag-to-reorder list shared by every reorderable collection in the
 * builder (course lessons, stage blocks, block questions, lesson
 * vocabulary). Each row keeps whatever markup the caller already renders —
 * this only prepends a drag handle and wires dnd-kit around it, so a row's
 * own buttons/inputs (accordion toggle, remove, edit fields) keep working
 * normally; only the handle itself starts a drag, matching the same
 * "handle-only, not whole-row" pattern used for the drag button below.
 */
export default function DragList<T extends { id: string }>({
  items,
  onReorder,
  renderItem,
  disabled,
  className,
}: {
  items: T[];
  onReorder: (ids: string[]) => void;
  renderItem: (item: T, index: number) => ReactNode;
  disabled?: boolean;
  className?: string;
}) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  if (disabled) {
    return <div className={className}>{items.map((item, i) => renderItem(item, i))}</div>;
  }

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const oldIndex = items.findIndex((item) => item.id === active.id);
    const newIndex = items.findIndex((item) => item.id === over.id);
    if (oldIndex === -1 || newIndex === -1) return;
    onReorder(arrayMove(items, oldIndex, newIndex).map((item) => item.id));
  };

  return (
    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
      <SortableContext items={items.map((item) => item.id)} strategy={verticalListSortingStrategy}>
        <div className={className}>
          {items.map((item, i) => (
            <DragRow key={item.id} id={item.id}>
              {renderItem(item, i)}
            </DragRow>
          ))}
        </div>
      </SortableContext>
    </DndContext>
  );
}

function DragRow({ id, children }: { id: string; children: ReactNode }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };
  return (
    <div ref={setNodeRef} style={style} className={`dnd-row ${isDragging ? "is-dragging" : ""}`}>
      <button type="button" className="dnd-handle" aria-label="Перетащить, чтобы изменить порядок" {...attributes} {...listeners}>
        ⠿
      </button>
      <div className="dnd-row__content">{children}</div>
    </div>
  );
}
