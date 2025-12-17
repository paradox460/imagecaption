#!/usr/bin/env -S deno run --allow-read --allow-net --allow-env
import OpenAI from "npm:openai@4";
import { encodeBase64 } from "https://deno.land/std@0.208.0/encoding/base64.ts";
import { jsonrepair } from "npm:jsonrepair@3.13.1";

const filePaths = Deno.args;

if (filePaths.length === 0) {
  console.error("Usage: deno run --allow-read --allow-net caption.ts <image1> <image2> ...");
  Deno.exit(1);
}

const client = new OpenAI({
  baseURL: "http://localhost:8088/v1",
  apiKey: ""
});

// Store connected WebSocket clients
const clients = new Set<WebSocket>();
let currentImageIndex = 0;
let isProcessing = false;

// Start HTTP server for serving the HTML interface
const HTTP_PORT = 8888;

async function serveHTTP() {
  const server = Deno.listen({ port: HTTP_PORT });
  console.log(`\x1b[32mHTTP Server running on http://localhost:${HTTP_PORT}\x1b[0m`);
  console.log(`\x1b[32mOpen your browser to view the interface\x1b[0m\n`);

  for await (const conn of server) {
    handleHTTP(conn);
  }
}

async function handleHTTP(conn: Deno.Conn) {
  const httpConn = Deno.serveHttp(conn);

  for await (const requestEvent of httpConn) {
    const url = new URL(requestEvent.request.url);

    if (url.pathname === "/") {
      // Serve the HTML file
      try {
        const html = await Deno.readTextFile("index.html");
        requestEvent.respondWith(
          new Response(html, {
            headers: { "content-type": "text/html" },
          })
        );
      } catch {
        requestEvent.respondWith(
          new Response("index.html not found", { status: 404 })
        );
      }
    } else if (url.pathname === "/ws") {
      // Handle WebSocket upgrade
      const upgrade = requestEvent.request.headers.get("upgrade") || "";
      if (upgrade.toLowerCase() === "websocket") {
        const { socket, response } = Deno.upgradeWebSocket(requestEvent.request);
        handleWebSocket(socket);
        requestEvent.respondWith(response);
      }
    } else {
      requestEvent.respondWith(
        new Response("Not found", { status: 404 })
      );
    }
  }
}

function handleWebSocket(socket: WebSocket) {
  clients.add(socket);
  console.log(`\x1b[36mClient connected. Total clients: ${clients.size}\x1b[0m`);

  socket.onopen = () => {
    // Send the first image when client connects
    if (currentImageIndex === 0 && !isProcessing) {
      processCurrentImage();
    }
  };

  socket.onmessage = async (event) => {
    try {
      const data = JSON.parse(event.data);
      await handleClientMessage(data);
    } catch (error) {
      console.error("Error handling message:", error);
    }
  };

  socket.onclose = () => {
    clients.delete(socket);
    console.log(`\x1b[36mClient disconnected. Total clients: ${clients.size}\x1b[0m`);
  };
}

async function handleClientMessage(data: { type: string; path?: string; caption?: string; tags?: string }) {
  switch (data.type) {
    case "accept":
      console.log(`\n\x1b[32m✓ ACCEPTED: ${data.path}\x1b[0m`);
      console.log(`Caption: ${data.caption}`);
      console.log(`Tags: ${data.tags}\n`);
      await moveToNextImage();
      break;

    case "reject":
      console.log(`\n\x1b[31m✗ REJECTED: ${data.path}\x1b[0m\n`);
      await moveToNextImage();
      break;

    case "regenerate":
      console.log(`\n\x1b[33m↻ REGENERATING: ${data.path}\x1b[0m\n`);
      await processCurrentImage();
      break;
  }
}

async function moveToNextImage() {
  currentImageIndex++;
  if (currentImageIndex < filePaths.length) {
    await processCurrentImage();
  } else {
    broadcast({ type: "complete" });
    console.log("\x1b[32m✓ All images processed!\x1b[0m");
  }
}

async function processCurrentImage() {
  if (isProcessing || currentImageIndex >= filePaths.length) return;

  isProcessing = true;
  const filePath = filePaths[currentImageIndex];

  try {
    console.log(`\x1b[32mProcessing [${currentImageIndex + 1}/${filePaths.length}]: ${filePath}\x1b[0m`);

    const imageData = await Deno.readFile(filePath);
    const base64Image = encodeBase64(imageData);

    const ext = filePath.split('.').pop()?.toLowerCase();
    const mimeType = ext === 'png' ? 'image/png' :
                     ext === 'jpg' || ext === 'jpeg' ? 'image/jpeg' :
                     ext === 'gif' ? 'image/gif' :
                     ext === 'webp' ? 'image/webp' : 'image/jpeg';

    // Send image to clients
    broadcast({
      type: "image",
      path: filePath,
      filename: filePath.split('/').pop(),
      data: base64Image,
      mimeType: mimeType
    });

    // Generate caption
    const response = await client.chat.completions.create({
      model: "Llama-Joycaption-Beta-One-Hf-Llava-Q4_K.gguf",
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image_url",
              image_url: {
                url: `data:${mimeType};base64,${base64Image}`,
              },
            },
            { type: "text", text: `Write a straightforward description for this image. Begin with the main subject and medium. Mention pivotal elements—people, objects, scenery—using confident, definite language. When describing people, pay particular attention to: Hair color (blonde, black hair, brunette, etc), race (white, black, asian), Gender, Tattoos, and clothing. Use bold, simple descriptions, such as colors, garment names, etc. Focus on concrete details like color, shape, quantity, texture, and spatial relationships. Show how elements interact. Omit mood and speculative wording. If text is present, quote it exactly. Note any watermarks, signatures, or compression artifacts. Never mention what's absent, resolution, or unobservable details. Vary your sentence structure and keep the description concise, without starting with "This image is…" or similar phrasing.

Write a json-formatted list of booru-like tags for this image.

Return the results in a JSON object, under the "description" and "tags" keys. Do not return any text outside the JSON. Do not return markdown, return just a raw json object
 ` },
          ],
        },
      ],
      max_tokens: 300,
    });

    const caption = response.choices[0].message.content;

    // Parse the caption
    let cleanedCaption = caption || "";
    cleanedCaption = cleanedCaption.replace(/```(?:json)?\s*/g, '').replace(/```\s*/g, '');
    cleanedCaption = cleanedCaption.trim();

    const repaired = JSON.parse(jsonrepair(cleanedCaption));

    console.log("Description:", repaired.description);
    console.log("Tags:", repaired.tags);

    // Send caption to clients
    broadcast({
      type: "caption",
      description: repaired.description,
      tags: repaired.tags
    });

  } catch (error) {
    console.error(`\x1b[31mError processing ${filePath}:\x1b[0m`, error.message);
    broadcast({
      type: "error",
      message: error.message
    });
  } finally {
    isProcessing = false;
  }
}

function broadcast(data: unknown) {
  const message = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Start the HTTP server
serveHTTP();
