/**
 * distroless 运行镜像无 shell/wget，用 Node 内置 http 做 HEALTHCHECK。
 * 与原先 wget 根路径一致：2xx/3xx/4xx 视为存活，5xx 或连不上则失败。
 */
import http from 'node:http';

const port = process.env.PORT || process.env.NITRO_PORT || 3000;

const req = http.get(`http://127.0.0.1:${port}/`, (res) => {
  process.exit(res.statusCode >= 200 && res.statusCode < 500 ? 0 : 1);
});

req.on('error', () => process.exit(1));
req.setTimeout(4000, () => {
  req.destroy();
  process.exit(1);
});
