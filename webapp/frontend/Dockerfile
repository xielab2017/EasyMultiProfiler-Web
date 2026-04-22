# ── EasyMultiProfiler – Frontend (Nginx) ─────────────────────────────────────
# Build context = webapp/ (set in docker-compose)
# No Node.js build step – pure HTML/CSS/JS served by Nginx
FROM nginx:1.25-alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY frontend/ /usr/share/nginx/html/
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
