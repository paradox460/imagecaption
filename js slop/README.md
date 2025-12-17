# Image Caption Tool

A web-based interface for generating and reviewing image captions using AI.

## Features

- 🖼️ Display images with side-by-side caption and tag editing
- 🔄 Real-time WebSocket communication
- ✅ Accept/Reject/Regenerate controls
- 🎨 Dark theme interface
- 📝 Editable captions and tags before accepting

## Prerequisites

- [Deno](https://deno.land/) installed
- Local AI server running on `http://localhost:8088/v1` with the Joycaption model

## Usage

### Start the Web Interface

```bash
./caption.ts <image1.jpg> <image2.png> ...
```

Or with explicit Deno command:

```bash
deno run --allow-read --allow-net --allow-env caption.ts image1.jpg image2.png
```

### Access the Interface

1. The script will start an HTTP server on `http://localhost:8080`
2. Open your browser and navigate to `http://localhost:8080`
3. The interface will automatically connect via WebSocket

### Workflow

1. **Image Display**: Images appear on the right side of the screen
2. **Caption Generation**: Captions and tags are automatically generated and appear in the text areas on the left
3. **Review**: Edit the caption or tags if needed
4. **Actions**:
   - **Accept**: Save the current caption/tags and move to the next image
   - **Reject**: Skip this image and move to the next
   - **Regenerate**: Generate a new caption for the current image

## Interface Layout

```
┌─────────────────────────────────────────────────────────┐
│                    Status & Filename                     │
├──────────────────────────┬──────────────────────────────┤
│                          │                              │
│   Caption Text Area      │                              │
│   (Editable)             │        Image Display         │
│                          │                              │
├──────────────────────────┤                              │
│                          │                              │
│   Tags Text Area         │                              │
│   (Editable)             │                              │
│                          │                              │
├──────────────────────────┴──────────────────────────────┤
│  [Accept]  [Reject]  [Regenerate]                       │
└─────────────────────────────────────────────────────────┘
```

## Terminal Output

The terminal will display:
- Server status and URL
- Processing progress (e.g., "Processing [1/5]: image.jpg")
- Generated descriptions and tags
- User actions (Accept ✓, Reject ✗, Regenerate ↻)

## Configuration

The script uses these settings by default:
- **HTTP Port**: 8080
- **AI Server**: http://localhost:8088/v1
- **Model**: Llama-Joycaption-Beta-One-Hf-Llava-Q4_K.gguf
- **Max Tokens**: 300

To modify these, edit the `caption.ts` file.

## Supported Image Formats

- PNG
- JPEG/JPG
- GIF
- WebP

## Notes

- Multiple browser tabs can connect simultaneously
- Captions and tags can be edited before accepting
- The script processes images sequentially
- Connection status is displayed in the interface