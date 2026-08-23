import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { callWoice } from "./client.mjs";

const statusParameters = { type: "object", properties: {}, additionalProperties: false };
const recordingParameters = {
  type: "object",
  properties: {
    recording_id: {
      type: "string",
      description: "Woice recording UUID",
    },
  },
  required: ["recording_id"],
  additionalProperties: false,
};
const searchParameters = {
  type: "object",
  properties: {
    query: { type: "string", description: "按空格分隔的 AND 搜索词" },
    offset: { type: "integer", minimum: 0 },
    limit: { type: "integer", minimum: 1, maximum: 100 },
  },
  additionalProperties: false,
};
const materialPageParameters = {
  type: "object",
  properties: {
    recording_id: { type: "string" },
    field: { type: "string", enum: ["transcript"] },
    offset: { type: "integer", minimum: 0 },
    limit: { type: "integer", minimum: 1, maximum: 16384 },
  },
  required: ["recording_id"],
  additionalProperties: false,
};

function textResult(value: unknown) {
  return {
    content: [{ type: "text", text: JSON.stringify(value, null, 2) }],
    details: value,
  };
}

function errorResult(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return {
    content: [{ type: "text", text: `Woice 请求失败：${message}` }],
    details: { error: message },
    isError: true,
  };
}

async function notifyStatus(ctx: any) {
  try {
    const result = await callWoice({ method: "woice.status" });
    ctx.ui.notify(`Woice：${result.state || "状态未知"}`, "info");
    return result;
  } catch (error) {
    ctx.ui.notify(`Woice 不可用：${error instanceof Error ? error.message : String(error)}`, "warning");
    throw error;
  }
}

/**
 * Thin PI adapter. All data access remains in Woice's versioned local RPC;
 * this extension never opens the SQLite database or touches microphone APIs.
 */
export default function registerWoiceExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "woice_status",
    label: "Woice 状态",
    description: "读取 Woice 当前录音和处理状态。",
    parameters: statusParameters as any,
    async execute() {
      try {
        return textResult(await callWoice({ method: "woice.status" }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerTool({
    name: "woice_list_recordings",
    label: "Woice 录音列表",
    description: "列出 Woice 中可用的录音 ID。",
    parameters: statusParameters as any,
    async execute() {
      try {
        return textResult(await callWoice({ method: "woice.list_recordings" }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerTool({
    name: "woice_read_transcript",
    label: "读取 Woice 原文",
    description: "读取指定录音的原始转录文本。",
    parameters: recordingParameters as any,
    async execute(_toolCallId: string, params: { recording_id: string }) {
      try {
        return textResult(await callWoice({
          method: "woice.read_transcript",
          parameters: { recording_id: params.recording_id },
        }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerTool({
    name: "woice_read_material",
    label: "读取 Woice 素材",
    description: "读取指定录音已持久化的素材状态、原文、时间戳和音轨引用；只读，不触发处理或外发。",
    parameters: recordingParameters as any,
    async execute(_toolCallId: string, params: { recording_id: string }) {
      try {
        return textResult(await callWoice({
          method: "woice.read_material",
          parameters: { recording_id: params.recording_id },
        }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerTool({
    name: "woice_search_materials",
    label: "搜索 Woice 素材",
    description: "只读搜索 Woice 素材；不会触发转写、外发或录音。",
    parameters: searchParameters as any,
    async execute(_toolCallId: string, params: { query?: string; offset?: number; limit?: number }) {
      try {
        return textResult(await callWoice({
          method: "woice.search_materials",
          parameters: {
            query: params.query || "",
            offset: String(params.offset || 0),
            limit: String(params.limit || 20),
          },
        }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerTool({
    name: "woice_read_material_page",
    label: "分页读取 Woice 原文",
    description: "只读分页读取指定录音的规范化原文；不会触发处理或外发。",
    parameters: materialPageParameters as any,
    async execute(
      _toolCallId: string,
      params: { recording_id: string; field?: string; offset?: number; limit?: number }
    ) {
      try {
        return textResult(await callWoice({
          method: "woice.read_material_page",
          parameters: {
            recording_id: params.recording_id,
            field: params.field || "transcript",
            offset: String(params.offset || 0),
            limit: String(params.limit || 16384),
          },
        }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerTool({
    name: "woice_request_markdown",
    label: "请求 Woice Markdown 笔记",
    description: "请求 Woice 对已有原文生成 Markdown 笔记；Woice 仍会在本机显示外发确认。",
    parameters: recordingParameters as any,
    async execute(
      _toolCallId: string,
      params: { recording_id: string },
      _signal: AbortSignal,
      _onUpdate: unknown,
      ctx: any
    ) {
      const confirmed = await ctx.ui.confirm(
        "请求 Woice Markdown 笔记",
        "Woice 将在自己的窗口中再次显示外发确认。是否继续？"
      );
      if (!confirmed) return textResult({ state: "cancelled", requires_user_confirmation: true });
      try {
        return textResult(await callWoice({
          method: "woice.request_transform",
          parameters: { recording_id: params.recording_id },
        }));
      } catch (error) {
        return errorResult(error);
      }
    },
  });

  pi.registerCommand("woice", {
    description: "显示 Woice 当前录音状态",
    handler: async (_args, ctx) => {
      try {
        await notifyStatus(ctx);
      } catch {
        // notifyStatus already gives the user an actionable message.
      }
    },
  });

  pi.registerShortcut("ctrl+shift+w", {
    description: "显示 Woice 当前录音状态",
    handler: async (_event, ctx) => {
      try {
        await notifyStatus(ctx);
      } catch {
        // notifyStatus already gives the user an actionable message.
      }
    },
  });
}
