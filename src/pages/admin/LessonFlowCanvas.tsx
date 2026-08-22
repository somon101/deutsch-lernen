import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import ReactFlow, {
  Background,
  Connection,
  Controls,
  Edge,
  Handle,
  MiniMap,
  Node,
  NodeProps,
  Panel,
  Position,
  ReactFlowProvider,
  addEdge,
  useEdgesState,
  useNodesState,
  useReactFlow,
} from "reactflow";
import "reactflow/dist/style.css";

/** One of the lesson's fixed steps (Слова/Материал/.../Итог) — content is
 * always derived live from real data; the canvas only remembers where it
 * sits and what it's connected to. */
export interface FlowStepDef {
  key: string;
  icon: string;
  accent: string;
  title: string;
  summary: string;
  preview?: string[];
  editable: boolean;
}

/** A purely decorative sticky-note node ("Разделитель") — the only node
 * type an admin can actually add from the palette, since every other node
 * is a fixed, always-present stage with no backing "create another one"
 * action. Its text is the only thing about it that isn't derived from real
 * lesson data, so it's the only piece worth persisting beyond position. */
interface NoteNodeData {
  kind: "note";
  text: string;
}

export interface SavedCanvasLayout {
  nodes: { id: string; position: { x: number; y: number }; note?: string }[];
  edges: { id: string; source: string; target: string }[];
}

/** Narrows the opaque JSON the server hands back (see courses.ts/content.ts
 * canvasLayout comments) into SavedCanvasLayout, or null for "nothing saved
 * yet" / anything unrecognized — so a malformed or pre-feature value never
 * crashes the canvas, it just falls back to the default arrangement. */
export function asCanvasLayout(value: unknown): SavedCanvasLayout | null {
  if (!value || typeof value !== "object") return null;
  const v = value as { nodes?: unknown; edges?: unknown };
  if (!Array.isArray(v.nodes) || !Array.isArray(v.edges)) return null;
  return v as SavedCanvasLayout;
}

type StepNodeData = FlowStepDef & { kind: "step" };
type FlowNodeData = StepNodeData | NoteNodeData;

const STEP_SPACING_X = 220;

function defaultPosition(index: number): { x: number; y: number } {
  return { x: 40 + index * STEP_SPACING_X, y: 160 };
}

function StepNode({ data, selected }: NodeProps<StepNodeData>) {
  return (
    <div className={`flow-card ${selected ? "is-open" : ""}`} style={{ "--flow-accent": data.accent } as React.CSSProperties}>
      <Handle type="target" position={Position.Left} />
      <div className="flow-card__head">
        <span className="flow-card__icon">{data.icon}</span>
      </div>
      <div className="flow-card__title">{data.title}</div>
      <div className="flow-card__summary">{data.summary}</div>
      {data.preview && data.preview.length > 0 && (
        <div className="flow-card__preview">
          {data.preview.map((p, i) => (
            <span className="flow-chip" key={i}>
              {p}
            </span>
          ))}
        </div>
      )}
      <Handle type="source" position={Position.Right} />
    </div>
  );
}

function NoteNode({ data, id }: NodeProps<NoteNodeData> & { id: string }) {
  const { setNodes } = useReactFlow();
  const update = (text: string) => setNodes((ns) => ns.map((n) => (n.id === id ? { ...n, data: { ...n.data, text } } : n)));
  return (
    <div className="flow-note">
      <Handle type="target" position={Position.Left} />
      <textarea
        className="flow-note__text"
        value={data.text}
        placeholder="Заметка / раздел…"
        onChange={(e) => update(e.target.value)}
      />
      <Handle type="source" position={Position.Right} />
    </div>
  );
}

const nodeTypes = { step: StepNode, note: NoteNode };

function buildDefaultEdges(stepKeys: string[]): Edge[] {
  const edges: Edge[] = [];
  for (let i = 0; i < stepKeys.length - 1; i++) {
    edges.push({ id: `e-${stepKeys[i]}-${stepKeys[i + 1]}`, source: stepKeys[i], target: stepKeys[i + 1] });
  }
  return edges;
}

function CanvasInner({
  steps,
  activeKey,
  onSelect,
  savedLayout,
  onSaveLayout,
}: {
  steps: FlowStepDef[];
  activeKey: string | null;
  onSelect: (key: string) => void;
  savedLayout: SavedCanvasLayout | null;
  onSaveLayout: (layout: SavedCanvasLayout) => Promise<unknown>;
}) {
  const { fitView } = useReactFlow();
  const stepKeys = useMemo(() => steps.map((s) => s.key), [steps]);
  const savedPositions = useMemo(() => new Map((savedLayout?.nodes ?? []).map((n) => [n.id, n.position])), [savedLayout]);

  const buildStepNodes = useCallback(
    (): Node<StepNodeData>[] =>
      steps.map((step, i) => ({
        id: step.key,
        type: "step",
        position: savedPositions.get(step.key) ?? defaultPosition(i),
        data: { ...step, kind: "step" },
        draggable: true,
      })),
    [steps, savedPositions],
  );

  const buildInitialNotes = useCallback((): Node<NoteNodeData>[] => {
    const noteEntries = (savedLayout?.nodes ?? []).filter((n) => n.id.startsWith("note-") && n.note !== undefined);
    return noteEntries.map((n) => ({
      id: n.id,
      type: "note",
      position: n.position,
      data: { kind: "note", text: n.note ?? "" },
    }));
  }, [savedLayout]);

  const [nodes, setNodes, onNodesChange] = useNodesState<FlowNodeData>([...buildStepNodes(), ...buildInitialNotes()]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>(savedLayout?.edges ?? buildDefaultEdges(stepKeys));

  // Live step data (title/summary/preview counts) can change on every save
  // elsewhere in the editor — keep those in sync without touching position,
  // selection, or any note/edge the admin has arranged.
  useEffect(() => {
    setNodes((current) => {
      const stepById = new Map(steps.map((s) => [s.key, s]));
      const withoutMissingSteps = current.filter((n) => n.type !== "step" || stepById.has(n.id));
      const existingIds = new Set(withoutMissingSteps.map((n) => n.id));
      const updated = withoutMissingSteps.map((n) =>
        n.type === "step" ? { ...n, data: { ...stepById.get(n.id)!, kind: "step" as const } } : n,
      );
      const added = steps
        .filter((s) => !existingIds.has(s.key))
        .map((s, i) => ({
          id: s.key,
          type: "step" as const,
          position: defaultPosition(steps.indexOf(s) + i),
          data: { ...s, kind: "step" as const },
          draggable: true,
        }));
      return [...updated, ...added];
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [steps]);

  // Kept in sync every render so a debounced save always reads the freshest
  // positions/text, however long ago it was scheduled — see scheduleSave.
  const nodesRef = useRef(nodes);
  const edgesRef = useRef(edges);
  nodesRef.current = nodes;
  edgesRef.current = edges;

  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [saveState, setSaveState] = useState<"idle" | "saving" | "saved">("idle");

  // Only ever called from an explicit user action below (drag stop, connect,
  // remove, adding/editing a note) — never from a generic "nodes changed"
  // effect, which would also fire for the live-data sync effect above (every
  // material/word/block save elsewhere replaces the node data, including
  // once on mount) and save a layout the admin never actually touched.
  const scheduleSave = useCallback(() => {
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      setSaveState("saving");
      const layout: SavedCanvasLayout = {
        nodes: nodesRef.current.map((n) => ({
          id: n.id,
          position: n.position,
          ...(n.data.kind === "note" ? { note: n.data.text } : {}),
        })),
        edges: edgesRef.current.map((e) => ({ id: e.id, source: e.source, target: e.target })),
      };
      try {
        await onSaveLayout(layout);
        setSaveState("saved");
      } catch {
        setSaveState("idle");
      }
    }, 800);
  }, [onSaveLayout]);

  const handleNodesChange: typeof onNodesChange = (changes) => {
    onNodesChange(changes);
    if (changes.some((c) => (c.type === "position" && c.dragging === false) || c.type === "remove")) scheduleSave();
  };
  const handleEdgesChange: typeof onEdgesChange = (changes) => {
    onEdgesChange(changes);
    if (changes.some((c) => c.type === "remove")) scheduleSave();
  };
  const onConnect = useCallback(
    (connection: Connection) => {
      setEdges((eds) => addEdge({ ...connection, id: `e-${connection.source}-${connection.target}-${Date.now()}` }, eds));
      scheduleSave();
    },
    [setEdges, scheduleSave],
  );

  // NoteNode edits its own text directly via useReactFlow().setNodes, so
  // that path can't call scheduleSave itself — instead this watches a
  // cheap serialized snapshot of just the note text, which only changes
  // when a note's content genuinely does (unlike `nodes` as a whole, which
  // also changes on every live-data sync above).
  const noteTextSnapshot = nodes
    .filter((n): n is Node<NoteNodeData> => n.type === "note")
    .map((n) => `${n.id}:${n.data.text}`)
    .join("|");
  const prevNoteTextSnapshot = useRef(noteTextSnapshot);
  useEffect(() => {
    if (prevNoteTextSnapshot.current !== noteTextSnapshot) {
      prevNoteTextSnapshot.current = noteTextSnapshot;
      scheduleSave();
    }
  }, [noteTextSnapshot, scheduleSave]);

  const addNote = () => {
    const id = `note-${Date.now()}`;
    // Staggered so a second/third note doesn't land exactly on top of the
    // last one — easy to miss and to click through if they perfectly
    // overlap, since every note starts at the same spot otherwise.
    const existingNotes = nodes.filter((n) => n.type === "note").length;
    const newNode: Node<NoteNodeData> = {
      id,
      type: "note",
      position: { x: 40 + existingNotes * 24, y: 340 + existingNotes * 24 },
      data: { kind: "note", text: "" },
    };
    setNodes((ns) => [...ns, newNode]);
    scheduleSave();
  };

  return (
    <div className="flow-canvas">
      <aside className="flow-palette">
        <div className="flow-palette__title">Блоки</div>
        {steps.map((s) => (
          <div className="flow-palette__item is-fixed" key={s.key} title="Уже есть на холсте — фиксированный этап урока">
            <span>{s.icon}</span> {s.title}
          </div>
        ))}
        <button type="button" className="flow-palette__item flow-palette__item--add" onClick={addNote}>
          <span>➕</span> Разделитель
        </button>
      </aside>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={handleNodesChange}
        onEdgesChange={handleEdgesChange}
        onConnect={onConnect}
        onNodeClick={(_, node) => {
          if (node.type === "step") onSelect(node.id);
        }}
        nodeTypes={nodeTypes}
        fitView
        minZoom={0.2}
        maxZoom={1.5}
        proOptions={{ hideAttribution: true }}
      >
        <Background gap={20} color="#2a2f4d" />
        <Controls showInteractive={false} className="flow-controls" />
        <MiniMap
          className="flow-minimap"
          maskColor="rgba(13,16,32,0.7)"
          nodeColor={(n) => (n.type === "step" ? (n.data as StepNodeData).accent : "#4a4f74")}
        />
        <Panel position="top-right" className="flow-toolbar">
          <button type="button" className="btn btn-ghost flow-toolbar__btn" onClick={() => fitView({ duration: 300 })}>
            По ширине
          </button>
          <span className={`flow-save-indicator ${saveState}`}>
            {saveState === "saving" ? "Сохраняем…" : saveState === "saved" ? "Черновик сохранён" : ""}
          </span>
        </Panel>
      </ReactFlow>
    </div>
  );
}

/**
 * Full-screen node-graph view of the lesson chain (React Flow), replacing
 * the static horizontal row of cards. Nodes for the 8 real steps are always
 * present and their content (title/summary/preview) is recomputed from live
 * data on every render — dragging, connecting, or adding a "Разделитель"
 * note only changes the *layout*, saved separately (see
 * LessonChainEditor's saveLayout prop) and never the lesson's real content.
 * Clicking a step node opens the same edit panel LessonChainEditor already
 * renders below the canvas.
 */
export default function LessonFlowCanvas(props: {
  steps: FlowStepDef[];
  activeKey: string | null;
  onSelect: (key: string) => void;
  savedLayout: SavedCanvasLayout | null;
  onSaveLayout: (layout: SavedCanvasLayout) => Promise<unknown>;
}) {
  return (
    <ReactFlowProvider>
      <CanvasInner {...props} />
    </ReactFlowProvider>
  );
}
