<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" import="java.sql.*,java.util.*,java.io.*" %>
<!doctype html><html lang="ja"><meta charset="UTF-8"><title>AWS Portfolio Day 1</title><body>
<h1>AWS Portfolio Day 1</h1>
<% Properties p=new Properties(); try(InputStream f=new FileInputStream("/etc/portfolio/db.properties")){p.load(f);} Class.forName("org.postgresql.Driver");
try(Connection c=DriverManager.getConnection(p.getProperty("url"),p.getProperty("user"),p.getProperty("password"));PreparedStatement s=c.prepareStatement("SELECT message FROM learning_log WHERE id=1");ResultSet r=s.executeQuery()){if(r.next()){%><p><%=r.getString(1)%></p><%}} %>
</body></html>
