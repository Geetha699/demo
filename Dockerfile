# Use the official NGINX image from Docker Hub
FROM nginx:latest

# Copy your static website content to the default NGINX directory
COPY index.html /usr/share/nginx/html/

# Expose port 80 for HTTP
EXPOSE 80

# Use the official NGINX image
FROM nginx:latest

# Set working directory
WORKDIR /usr/share/nginx/html

# Remove the default NGINX static content
RUN rm -rf ./*

# Copy the static site contentto NGINX's web root directory
COPY . .

# Expose port 80
EXPOSE 80

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]


