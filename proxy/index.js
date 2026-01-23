import app from './app.js';

const PORT = 4096;

app.listen(PORT, () => {
    console.log(`OpenCode OpenAI Proxy listening on port ${PORT}`);
    console.log(`Forwarding to OpenCode Server on port 4097`);
});
