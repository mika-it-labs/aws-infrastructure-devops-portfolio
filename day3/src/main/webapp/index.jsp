<%@ page contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" import="java.sql.*,java.util.*,java.io.*" %>
<%! private String escape(String s) { return s == null ? "" : s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;"); } %>
<!doctype html><html lang="ja"><meta charset="UTF-8"><title>AWS Portfolio Day 3</title><body>
<h1>AWS Portfolio Day 3</h1><p>Maven WAR / Tomcat container / CI/CD</p>
<%
Properties p = new Properties();
File dbConfig = new File("/etc/portfolio/db.properties");
if (dbConfig.isFile()) { try (InputStream f = new FileInputStream(dbConfig)) { p.load(f); } }
String url = System.getenv("DB_URL");
if (url == null || url.isEmpty()) url = p.getProperty("url");
String user = System.getenv("DB_USER");
if (user == null || user.isEmpty()) user = p.getProperty("user");
String password = System.getenv("DB_PASSWORD");
if (password == null) password = p.getProperty("password");
if (url == null || url.isEmpty()) {
%><p>DB_STATUS=UNCONFIGURED</p><p>DB接続は未設定です。</p><%
} else {
  Class.forName("org.postgresql.Driver");
  try (Connection c = DriverManager.getConnection(url, user, password);
       PreparedStatement s = c.prepareStatement("SELECT message FROM learning_log WHERE id=1");
       ResultSet r = s.executeQuery()) {
    if (r.next()) { %><p><%=escape(r.getString(1))%></p><p>DB_STATUS=CONNECTED</p><% }
    else { response.setStatus(503); %><p>DB_STATUS=EMPTY</p><% }
  } catch (SQLException e) { response.setStatus(503); %><p>DB_STATUS=ERROR</p><% }
}
%></body></html>
