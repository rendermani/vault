FROM nginx:alpine

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create nginx user and set permissions
RUN addgroup -g 1001 nginx-user && \
    adduser -D -s /bin/sh -u 1001 -G nginx-user nginx-user

# Set working directory
WORKDIR /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/progress.json || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]