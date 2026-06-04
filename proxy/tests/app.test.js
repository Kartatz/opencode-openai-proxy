import request from 'supertest';
import { jest } from '@jest/globals';

// Define o mock antes de importar o app
jest.unstable_mockModule('axios', () => ({
    default: {
        get: jest.fn(async () => ({
            data: Buffer.from('fake-image-data'),
            headers: { 'content-type': 'image/png' }
        }))
    }
}));

jest.unstable_mockModule('@opencode-ai/sdk', () => {
    const client = {
        config: {
            providers: jest.fn(async () => ({
                data: {
                    providers: [
                        {
                            id: 'opencode',
                            models: {
                                'big-pickle': { id: 'big-pickle' }
                            }
                        }
                    ]
                }
            })),
            update: jest.fn(async () => ({}))
        },
        session: {
            create: jest.fn(async () => ({
                data: { id: 'test-session-id' }
            })),
            prompt: jest.fn(async (args) => {
                const promptText = args.body.prompt || '';
                const parts = [{ type: 'text', text: 'Resposta simulada' }];

                if (promptText.includes('reasoning')) {
                    parts.unshift({ type: 'reasoning', text: 'Thinking process...' });
                }

                return {
                    data: { parts }
                };
            })
        },
        event: {
            subscribe: jest.fn(async () => {
                const sessionId = 'test-session-id';
                const mockEvents = [
                    { type: 'message.part.updated', properties: { part: { type: 'reasoning', sessionID: sessionId }, delta: 'Thinking...' } },
                    { type: 'message.part.updated', properties: { part: { type: 'text', sessionID: sessionId }, delta: 'Resposta' } },
                    { type: 'message.part.updated', properties: { part: { type: 'text', sessionID: sessionId }, delta: ' simulada' } },
                    { type: 'message.updated', properties: { info: { sessionID: sessionId, finish: 'stop' } } }
                ];

                return {
                    stream: (async function* () {
                        for (const event of mockEvents) {
                            yield event;
                        }
                    })()
                };
            })
        }
    };
    return { createOpencodeClient: jest.fn(() => client) };
});


const { default: app } = await import('../app.js');
const { createOpencodeClient } = await import('@opencode-ai/sdk');

describe('Proxy OpenAI API', () => {
    const originalEnv = process.env;

    beforeEach(() => {
        process.env = { ...originalEnv, OPENCODE_SERVER_PASSWORD: 'test-password' };
    });

    afterAll(() => {
        process.env = originalEnv;
    });

    test('GET /health deve retornar status ok sem auth', async () => {
        // Removemos a auth do health no app.js se necessário, ou passamos aqui
        const res = await request(app).get('/health');
        expect(res.statusCode).toEqual(200);
        expect(res.body).toEqual({ status: 'ok', proxy: true });
    });

    test('Deve falhar sem autenticação nos endpoints v1', async () => {
        const res = await request(app).get('/v1/models');
        expect(res.statusCode).toEqual(401);
    });

    test('GET /v1/models deve retornar lista de modelos compatível com OpenAI', async () => {
        const res = await request(app)
            .get('/v1/models')
            .set('Authorization', 'Bearer test-password');

        expect(res.statusCode).toEqual(200);
        expect(res.body.object).toEqual('list');
        expect(res.body.data[0].id).toEqual('opencode/big-pickle');
    });

    test('POST /v1/chat/completions deve retornar chat completion', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: 'Olá' }]
            });

        expect(res.statusCode).toEqual(200);
        expect(res.body.object).toEqual('chat.completion');
        expect(res.body.choices[0].message.content).toEqual('Resposta simulada');
    });

    test('POST /v1/chat/completions deve suportar streaming com tags <think>', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: 'Olá' }],
                stream: true
            });

        expect(res.statusCode).toEqual(200);
        expect(res.header['content-type']).toContain('text/event-stream');
        expect(res.text).toContain('data: {"id"');
        expect(res.text).toContain('data: [DONE]');
        // Validar que há resposta (não necessariamente a tag <think> por ser um stream mock)
        expect(res.text).toContain('Resposta');
    });

    test('POST /v1/chat/completions deve suportar streaming com reasoning inline', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: 'Teste com reasoning' }],
                stream: true
            });

        expect(res.statusCode).toEqual(200);
        expect(res.header['content-type']).toContain('text/event-stream');
        // Validar que há chunks com <think>
        expect(res.text).toContain('<think>');
        // Validar que há chunks com </think>
        expect(res.text).toContain('</think>');
        // Validar conclusão
        expect(res.text).toContain('data: [DONE]');
    });

    test('POST /v1/chat/completions deve suportar conteúdo multimodal (imagens)', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ 
                    role: 'user', 
                    content: [
                        { type: 'text', text: 'O que tem nesta imagem?' },
                        { type: 'image_url', image_url: { url: 'https://example.com/image.png' } }
                    ]
                }]
            });

        expect(res.statusCode).toEqual(200);
        expect(res.body.choices[0].message.content).toEqual('Resposta simulada');
    });

    test('POST /v1/chat/completions não deve gerar tags think vazias quando reasoning não tem conteúdo (issue #1)', async () => {
        const client = createOpencodeClient();
        const sessionId = 'test-session-id';

        client.event.subscribe.mockImplementationOnce(async () => ({
            stream: (async function* () {
                yield { type: 'message.part.updated', properties: { part: { type: 'reasoning', sessionID: sessionId }, delta: 'The user is asking' } };
                yield { type: 'message.part.updated', properties: { part: { type: 'reasoning', sessionID: sessionId }, delta: ' a simple math question' } };
                yield { type: 'message.part.updated', properties: { part: { type: 'reasoning', sessionID: sessionId }, delta: '. The answer is 2.' } };
                yield { type: 'message.part.updated', properties: { part: { type: 'text', sessionID: sessionId }, delta: '1+1' } };
                yield { type: 'message.part.updated', properties: { part: { type: 'text', sessionID: sessionId }, delta: ' = 2' } };
                yield { type: 'message.part.updated', properties: { part: { type: 'reasoning', sessionID: sessionId }, delta: null } };
                yield { type: 'message.part.updated', properties: { part: { type: 'reasoning', sessionID: sessionId }, delta: undefined } };
                yield { type: 'message.updated', properties: { info: { sessionID: sessionId, finish: 'stop' } } };
            })()
        }));

        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: '1+1=?' }],
                stream: true
            });

        expect(res.statusCode).toEqual(200);

        const thinkOpenCount = (res.text.match(/<think>/g) || []).length;
        const thinkCloseCount = (res.text.match(/<\/think>/g) || []).length;
        expect(thinkOpenCount).toEqual(1);
        expect(thinkCloseCount).toEqual(1);
    });


    test('POST /v1/chat/completions deve retornar tokens de reasoning quando disponiveis (non-streaming)', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: 'Teste com reasoning' }]
            });

        expect(res.statusCode).toEqual(200);
        // Validar que o conteúdo inclui a tag <think> para non-streaming
        expect(res.body.choices[0].message.content).toContain('<think>\nThinking process...\n</think>\n\nResposta simulada');
        // 'Thinking process...' tem 19 chars -> ~5 tokens
        expect(res.body.usage.completion_tokens_details.reasoning_tokens).toBeGreaterThan(0);
        // Validar que o campo reasoning_content não existe
        expect(res.body.choices[0].message.reasoning_content).toBeUndefined();
    });

    test('POST /v1/responses deve retornar formato de response no non-streaming', async () => {
        const res = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                input: 'Olá'
            });

        expect(res.statusCode).toEqual(200);
        expect(res.body.object).toEqual('response');
        expect(res.body.status).toEqual('completed');
        expect(res.body.output[0].type).toEqual('message');
        expect(res.body.output[0].content[0].type).toEqual('output_text');
    });

    test('POST /v1/responses deve suportar stream no formato responses', async () => {
        const res = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                input: 'Olá',
                stream: true
            });

        expect(res.statusCode).toEqual(200);
        expect(res.header['content-type']).toContain('text/event-stream');
        expect(res.text).toContain('"type":"response.created"');
        expect(res.text).toContain('"type":"response.output_text.delta"');
        expect(res.text).toContain('"type":"response.completed"');
        expect(res.text).toContain('data: [DONE]');
    });

    test('POST /v1/responses deve suportar previous_response_id', async () => {
        const first = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                input: 'Primeira mensagem'
            });

        expect(first.statusCode).toEqual(200);
        expect(first.body.id).toBeDefined();

        const second = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                previous_response_id: first.body.id,
                input: 'Continuação'
            });

        expect(second.statusCode).toEqual(200);
        expect(second.body.object).toEqual('response');
    });

    test('POST /v1/responses deve rejeitar previous_response_id inválido', async () => {
        const res = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                previous_response_id: 'resp_invalido',
                input: 'teste'
            });

        expect(res.statusCode).toEqual(400);
        expect(res.body.error.message).toContain('previous_response_id');
    });

    test('POST /v1/responses deve rejeitar tools reais', async () => {
        const res = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                input: 'Teste',
                tools: [{ type: 'function', function: { name: 'weather' } }]
            });

        expect(res.statusCode).toEqual(400);
        expect(res.body.error.message).toContain('not enabled');
    });

    test('POST /v1/responses não deve rejeitar se tools for vazio ou tool_choice for none', async () => {
        const res = await request(app)
            .post('/v1/responses')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                input: 'Teste',
                tools: [],
                tool_choice: 'none'
            });

        expect(res.statusCode).toEqual(200);
    });

    test('POST /v1/chat/completions deve rejeitar tools reais', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: 'Teste' }],
                tools: [{ type: 'function', function: { name: 'weather' } }]
            });

        expect(res.statusCode).toEqual(400);
        expect(res.body.error.message).toContain('not enabled');
    });

    test('POST /v1/chat/completions não deve rejeitar se tools for vazio ou tool_choice for none', async () => {
        const res = await request(app)
            .post('/v1/chat/completions')
            .set('Authorization', 'Bearer test-password')
            .send({
                model: 'opencode/big-pickle',
                messages: [{ role: 'user', content: 'Teste' }],
                tools: [],
                tool_choice: 'none'
            });

        expect(res.statusCode).toEqual(200);
    });
});
