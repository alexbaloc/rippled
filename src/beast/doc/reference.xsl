<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">

<!--
  Copyright (c) 2003-2015 Christopher M. Kohlhoff (chris at kohlhoff dot com)

  Distributed under the Boost Software License, Version 1.0. (See accompanying
  file LICENSE_1_0.txt or copy at http://www.beast.org/LICENSE_1_0.txt)
-->

<xsl:output method="text"/>
<xsl:strip-space elements="*"/>
<xsl:preserve-space elements="para"/>


<xsl:variable name="newline">
<xsl:text>
</xsl:text>
</xsl:variable>

<!--
  Loop over all top-level documentation elements (i.e. classes, functions,
  variables and typedefs at namespace scope). The elements are sorted by name.
  Anything in a "detail" namespace or with "_handler" in the name is skipped.
-->
<xsl:template match="/doxygen">
<xsl:text>[/
    Copyright (c) 2013-2016 Vinnie Falco (vinnie dot falco at gmail dot com)

    Distributed under the Boost Software License, Version 1.0. (See accompanying
    file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
]

[section:ref Reference]

</xsl:text>
  <xsl:for-each select="
      compounddef[@kind = 'class' or @kind = 'struct'] |
      compounddef[@kind = 'namespace']/sectiondef/memberdef">
    <xsl:sort select="concat((. | ancestor::*)/compoundname, '::', name, ':x')"/>
    <xsl:sort select="name"/>
    <xsl:choose>
      <xsl:when test="@kind='class' or @kind='struct'">
        <xsl:call-template name="class"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="namespace-memberdef"/>
      </xsl:otherwise>
      <!--
      <xsl:when test="@kind='class' or @kind='struct'">
        <xsl:if test="
            contains(compoundname, 'beast::') and
            not(contains(compoundname, '::detail'))">
          <xsl:call-template name="class"/>
        </xsl:if>
      </xsl:when>
      <xsl:otherwise>
        <xsl:if test="
            not(contains(ancestor::*/compoundname, '::detail')) and
            not(contains(ancestor::*/compoundname, '::service::key')) and
            not(contains(ancestor::*/compoundname, '_helper')) and
            not(contains(name, '_helper')) and
            not(contains(name, 'io_service_impl'))">
          <xsl:call-template name="namespace-memberdef"/>
        </xsl:if>
      </xsl:otherwise>
    -->
    </xsl:choose>
  </xsl:for-each>
  <xsl:text>&#xd;[endsect]</xsl:text>
</xsl:template>


<!--========== Utilities ==========-->

<xsl:template name="strip-beast-ns">
  <xsl:param name="name"/>
  <xsl:choose>
    <xsl:when test="contains($name, 'boost::system::is_error_code_enum')">
      <xsl:value-of select="$name"/>
    </xsl:when>
    <xsl:when test="contains($name, 'beast::')">
      <xsl:value-of select="substring-after($name, 'beast::')"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$name"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template name="strip-ns">
  <xsl:param name="name"/>
  <xsl:choose>
    <xsl:when test="contains($name, 'boost::system::is_error_code_enum')">
      <xsl:value-of select="$name"/>
    </xsl:when>
    <xsl:when test="contains($name, '::') and contains($name, '&lt;')">
      <xsl:choose>
        <xsl:when test="string-length(substring-before($name, '::')) &lt; string-length(substring-before($name, '&lt;'))">
          <xsl:call-template name="strip-ns">
            <xsl:with-param name="name" select="substring-after($name, '::')"/>
          </xsl:call-template>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="$name"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:when>
    <xsl:when test="contains($name, '::')">
      <xsl:call-template name="strip-ns">
        <xsl:with-param name="name" select="substring-after($name, '::')"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$name"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template name="cleanup-type">
  <xsl:param name="name"/>
  <xsl:variable name="type">
    <xsl:choose>
      <xsl:when test="contains($name, 'BOOST_ASIO_DECL ')">
        <xsl:value-of select="substring-after($name, 'BOOST_ASIO_DECL ')"/>
      </xsl:when>
      <xsl:when test="contains($name, 'BOOST_ASIO_DECL')">
        <xsl:value-of select="substring-after($name, 'BOOST_ASIO_DECL')"/>
      </xsl:when>
      <xsl:when test="$name = 'virtual'"></xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$name"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:variable>
  <xsl:choose>
    <xsl:when test="$type='ConstBufferSequence'">
      <xsl:text>``[link beast.ref.ConstBufferSequence ['ConstBufferSequence]]``</xsl:text>
    </xsl:when>
    <xsl:when test="$type='implementation_defined'">
      <xsl:text>``['implementation-defined]``</xsl:text>
    </xsl:when>
    <xsl:when test="$type='void_or_deduced'">
      <xsl:text>``[link beast.ref.asynchronous_operations.return_type_of_an_initiating_function ['void-or-deduced]]``</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$type"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<xsl:template name="make-id">
  <xsl:param name="name"/>
  <xsl:choose>
    <xsl:when test="contains($name, 'boost::system::')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="substring-after($name, 'boost::system::')"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, 'boost::asio::error::')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, 'boost::asio::error::'), substring-after($name, 'boost::asio::error::'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '::')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '::'), '__', substring-after($name, '::'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '=')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '='), '_eq_', substring-after($name, '='))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '!')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '!'), '_not_', substring-after($name, '!'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '-&gt;')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '-&gt;'), '_arrow_', substring-after($name, '-&gt;'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '&lt;')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '&lt;'), '_lt_', substring-after($name, '&lt;'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '&gt;')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '&gt;'), '_gt_', substring-after($name, '&gt;'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '[')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '['), '_lb_', substring-after($name, '['))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, ']')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, ']'), '_rb_', substring-after($name, ']'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '(')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '('), '_lp_', substring-after($name, '('))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, ')')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, ')'), '_rp_', substring-after($name, ')'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '+')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '+'), '_plus_', substring-after($name, '+'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '-')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '-'), '_minus_', substring-after($name, '-'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '*')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '*'), '_star_', substring-after($name, '*'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, '~')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, '~'), '_', substring-after($name, '~'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, ' ')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, ' '), '_', substring-after($name, ' '))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($name, 'boost__posix_time__ptime')">
      <xsl:call-template name="make-id">
        <xsl:with-param name="name"
         select="concat(substring-before($name, 'boost__posix_time__ptime'), 'ptime', substring-after($name, 'boost__posix_time__ptime'))"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$name"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

<!--========== Markup ==========-->

<xsl:template match="para" mode="markup">
  <xsl:apply-templates mode="markup"/>
  <xsl:text>&#xd;</xsl:text>
</xsl:template>

<xsl:template match="para" mode="markup-nested">
  <xsl:apply-templates mode="markup-nested"/>
</xsl:template>

<xsl:template match="title" mode="markup">
  <xsl:variable name="title">
    <xsl:value-of select="."/>
  </xsl:variable>
  <xsl:if test="string-length($title) > 0">
    <xsl:text>[heading </xsl:text>
    <xsl:value-of select="."/>
    <xsl:text>]</xsl:text>
  </xsl:if>
</xsl:template>

<xsl:template match="programlisting" mode="markup">
  <xsl:value-of select="$newline"/>
  <xsl:value-of select="$newline"/>
  <xsl:apply-templates mode="codeline"/>
  <xsl:value-of select="$newline"/>
  <xsl:value-of select="$newline"/>
</xsl:template>

<xsl:template match="programlisting" mode="markup-nested">
  <xsl:value-of select="$newline"/>
  <xsl:text>``</xsl:text>
  <xsl:value-of select="$newline"/>
  <xsl:apply-templates mode="codeline"/>
  <xsl:if test="substring(., string-length(.)) = $newline">
    <xsl:value-of select="$newline"/>
  </xsl:if>
  <xsl:text>``</xsl:text>
  <xsl:value-of select="$newline"/>
</xsl:template>

<xsl:template match="codeline" mode="codeline">
  <xsl:if test="string-length(.) &gt; 0">
    <xsl:text>  </xsl:text>
  </xsl:if>
  <xsl:apply-templates mode="codeline"/>
  <xsl:value-of select="$newline"/>
</xsl:template>

<xsl:template match="sp" mode="markup">
  <xsl:text> </xsl:text>
</xsl:template>

<xsl:template match="sp" mode="markup-nested">
  <xsl:text> </xsl:text>
</xsl:template>

<xsl:template match="sp" mode="codeline">
  <xsl:text> </xsl:text>
</xsl:template>

<xsl:template match="linebreak" mode="markup">
  <xsl:text>&#xd;&#xd;</xsl:text>
</xsl:template>

<xsl:template match="linebreak" mode="markup-nested">
  <xsl:text>&#xd;&#xd;</xsl:text>
</xsl:template>

<xsl:template match="computeroutput" mode="markup">
  <xsl:text>`</xsl:text>
  <xsl:value-of select="."/>
  <xsl:text>`</xsl:text>
</xsl:template>

<xsl:template match="computeroutput" mode="markup-nested">
  <xsl:text>`</xsl:text>
  <xsl:value-of select="."/>
  <xsl:text>`</xsl:text>
</xsl:template>

<xsl:template match="listitem" mode="markup">
  <xsl:text>* </xsl:text>
  <xsl:call-template name="strip-leading-whitespace">
    <xsl:with-param name="text">
      <xsl:apply-templates mode="markup"/>
    </xsl:with-param>
  </xsl:call-template>
</xsl:template>

<xsl:template match="bold" mode="markup">[*<xsl:apply-templates mode="markup"/>]</xsl:template>

<xsl:template match="emphasis" mode="markup">['<xsl:apply-templates mode="markup"/>]</xsl:template>

<xsl:template match="parameterlist" mode="markup">
  <xsl:choose>
    <xsl:when test="@kind='param'">
      <xsl:text>[heading Parameters]&#xd;</xsl:text>
    </xsl:when>
    <xsl:when test="@kind='exception'">
      <xsl:text>[heading Exceptions]&#xd;</xsl:text>
    </xsl:when>
  </xsl:choose>
  <xsl:text>[variablelist&#xd;</xsl:text>
  <xsl:apply-templates mode="markup"/>
  <xsl:text>]&#xd;</xsl:text>
</xsl:template>

<xsl:template match="parameteritem" mode="markup">
  <xsl:text>  [[</xsl:text>
  <xsl:value-of select="parameternamelist"/>
  <xsl:text>][&#xd;    </xsl:text>
  <xsl:apply-templates select="parameterdescription" mode="markup-nested"/>
  <xsl:text>&#xd;  ]]&#xd;</xsl:text>
</xsl:template>



<xsl:template match="simplesect" mode="markup">
  <xsl:choose>
    <xsl:when test="@kind='return'">
      <xsl:text>[heading Return Value]</xsl:text>
      <xsl:apply-templates mode="markup"/>
    </xsl:when>
    <xsl:when test="@kind='see'">
    </xsl:when>
    <xsl:when test="@kind='note'">
      <xsl:text>[heading Remarks]&#xd;</xsl:text>
      <xsl:apply-templates mode="markup"/>
    </xsl:when>
    <xsl:when test="@kind='par'">
      <xsl:if test="not(starts-with(title, 'Concepts:'))">
        <xsl:apply-templates mode="markup"/>
      </xsl:if>
    </xsl:when>
    <xsl:otherwise>
      <xsl:apply-templates mode="markup"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>



<xsl:template match="text()" mode="markup">
  <xsl:variable name="text" select="."/>
  <xsl:variable name="starts-with-whitespace" select="
      starts-with($text, ' ') or starts-with($text, $newline)"/>
  <xsl:variable name="preceding-node-name">
    <xsl:for-each select="preceding-sibling::*">
      <xsl:if test="position() = last()">
        <xsl:value-of select="local-name()"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>
  <xsl:variable name="after-newline" select="
      $preceding-node-name = 'programlisting' or
      $preceding-node-name = 'linebreak'"/>
  <xsl:choose>
    <xsl:when test="$starts-with-whitespace and $after-newline">
      <xsl:call-template name="escape-text">
        <xsl:with-param name="text">
          <xsl:call-template name="strip-leading-whitespace">
            <xsl:with-param name="text" select="$text"/>
          </xsl:call-template>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:call-template name="escape-text">
        <xsl:with-param name="text" select="$text"/>
      </xsl:call-template>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template match="text()" mode="markup-nested">
  <xsl:variable name="text" select="."/>
  <xsl:variable name="starts-with-whitespace" select="
      starts-with($text, ' ') or starts-with($text, $newline)"/>
  <xsl:variable name="preceding-node-name">
    <xsl:for-each select="preceding-sibling::*">
      <xsl:if test="position() = last()">
        <xsl:value-of select="local-name()"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>
  <xsl:variable name="after-newline" select="
      $preceding-node-name = 'programlisting' or
      $preceding-node-name = 'linebreak'"/>
  <xsl:choose>
    <xsl:when test="$starts-with-whitespace and $after-newline">
      <xsl:call-template name="escape-text">
        <xsl:with-param name="text">
          <xsl:call-template name="strip-leading-whitespace">
            <xsl:with-param name="text" select="$text"/>
          </xsl:call-template>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:call-template name="escape-text">
        <xsl:with-param name="text" select="$text"/>
      </xsl:call-template>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template name="strip-leading-whitespace">
  <xsl:param name="text"/>
  <xsl:choose>
    <xsl:when test="starts-with($text, ' ')">
      <xsl:call-template name="strip-leading-whitespace">
        <xsl:with-param name="text" select="substring($text, 2)"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="starts-with($text, $newline)">
      <xsl:call-template name="strip-leading-whitespace">
        <xsl:with-param name="text" select="substring($text, 2)"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$text"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template name="escape-text">
  <xsl:param name="text"/>
  <xsl:choose>
    <xsl:when test="contains($text, '_')">
      <xsl:value-of select="substring-before($text, '_')"/>
      <xsl:text>\_</xsl:text>
      <xsl:call-template name="escape-text">
        <xsl:with-param name="text" select="substring-after($text, '_')"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$text"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template name="escape-name">
  <xsl:param name="text"/>
  <xsl:choose>
    <xsl:when test="contains($text, '[')">
      <xsl:value-of select="substring-before($text, '[')"/>
      <xsl:text>\[</xsl:text>
      <xsl:call-template name="escape-name">
        <xsl:with-param name="text" select="substring-after($text, '[')"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="contains($text, ']')">
      <xsl:value-of select="substring-before($text, ']')"/>
      <xsl:text>\]</xsl:text>
      <xsl:call-template name="escape-name">
        <xsl:with-param name="text" select="substring-after($text, ']')"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$text"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template match="ref[@kindref='compound']" mode="markup">
  <xsl:variable name="name">
    <xsl:value-of select="."/>
  </xsl:variable>
  <xsl:choose>
    <xsl:when test="contains(@refid, 'asio') or contains($name, 'asio::')">
      <xsl:variable name="dox-ref-id" select="@refid"/>
      <xsl:variable name="ref-name">
        <xsl:call-template name="strip-beast-ns">
          <xsl:with-param name="name"
            select="(/doxygen//compounddef[@id=$dox-ref-id])[1]/compoundname"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="ref-id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$ref-name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:text>[link beast.ref.</xsl:text>
      <xsl:value-of select="$ref-id"/>
      <xsl:text> `</xsl:text>
      <xsl:value-of name="text" select="$ref-name"/>
      <xsl:text>`]</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:text>`</xsl:text>
      <xsl:value-of select="."/>
      <xsl:text>`</xsl:text>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template match="ref[@kindref='compound']" mode="markup-nested">
  <xsl:variable name="name">
    <xsl:value-of select="."/>
  </xsl:variable>
  <xsl:choose>
    <xsl:when test="contains(@refid, 'asio') or contains($name, 'asio::')">
      <xsl:variable name="dox-ref-id" select="@refid"/>
      <xsl:variable name="ref-name">
        <xsl:call-template name="strip-beast-ns">
          <xsl:with-param name="name"
            select="(/doxygen//compounddef[@id=$dox-ref-id])[1]/compoundname"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="ref-id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$ref-name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:text>[link beast.ref.</xsl:text>
      <xsl:value-of select="$ref-id"/>
      <xsl:text> `</xsl:text>
      <xsl:value-of name="text" select="$ref-name"/>
      <xsl:text>`]</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:text>`</xsl:text>
      <xsl:value-of select="."/>
      <xsl:text>`</xsl:text>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template match="ref[@kindref='member']" mode="markup">
  <xsl:variable name="dox-ref-id" select="@refid"/>
  <xsl:variable name="memberdefs" select="/doxygen//compounddef/sectiondef/memberdef[@id=$dox-ref-id]"/>
  <xsl:choose>
    <xsl:when test="contains(@refid, 'namespaceboost_1_1asio') and count($memberdefs) &gt; 0">
      <xsl:variable name="dox-compound-name" select="($memberdefs)[1]/../../compoundname"/>
      <xsl:variable name="dox-name" select="($memberdefs)[1]/name"/>
      <xsl:variable name="ref-name">
        <xsl:call-template name="strip-beast-ns">
          <xsl:with-param name="name" select="concat($dox-compound-name,'::',$dox-name)"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="ref-id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$ref-name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:text>[link beast.ref.</xsl:text>
      <xsl:value-of select="$ref-id"/>
      <xsl:text> `</xsl:text>
      <xsl:value-of name="text" select="$ref-name"/>
      <xsl:text>`]</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:text>`</xsl:text>
      <xsl:value-of select="."/>
      <xsl:text>`</xsl:text>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>


<xsl:template match="ref[@kindref='member']" mode="markup-nested">
  <xsl:variable name="dox-ref-id" select="@refid"/>
  <xsl:variable name="memberdefs" select="/doxygen//compounddef/sectiondef/memberdef[@id=$dox-ref-id]"/>
  <xsl:choose>
    <xsl:when test="contains(@refid, 'namespaceboost_1_1asio') and count($memberdefs) &gt; 0">
      <xsl:variable name="dox-compound-name" select="($memberdefs)[1]/../../compoundname"/>
      <xsl:variable name="dox-name" select="($memberdefs)[1]/name"/>
      <xsl:variable name="ref-name">
        <xsl:call-template name="strip-beast-ns">
          <xsl:with-param name="name" select="concat($dox-compound-name,'::',$dox-name)"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="ref-id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$ref-name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:text>[link beast.ref.</xsl:text>
      <xsl:value-of select="$ref-id"/>
      <xsl:text> `</xsl:text>
      <xsl:value-of name="text" select="$ref-name"/>
      <xsl:text>`]</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:text>`</xsl:text>
      <xsl:value-of select="."/>
      <xsl:text>`</xsl:text>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>



<xsl:template name="header-requirements">
  <xsl:param name="file"/>
  <xsl:value-of select="$newline"/>
  <xsl:text>[heading Requirements]&#xd;</xsl:text>
  <xsl:text>['Header: ][^</xsl:text>
  <xsl:value-of select="substring-after($file, 'beast/')"/>
  <xsl:text>] &#xd;&#xd;</xsl:text>
  <xsl:text>['Convenience header: ]</xsl:text>
  <xsl:choose>
    <xsl:when test="contains($file, 'beast/asio')">
      <xsl:text>[^beast/asio.h]</xsl:text>
    </xsl:when>
    <xsl:when test="contains($file, 'beast/http')">
      <xsl:text>[^beast/http.h]</xsl:text>
    </xsl:when>
    <xsl:when test="contains($file, 'beast/wsproto')">
      <xsl:text>[^beast/wsproto.h]</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="$file"/>
    </xsl:otherwise>
  </xsl:choose>
  <xsl:value-of select="$newline"/>
</xsl:template>


<!--========== Class ==========-->

<xsl:template name="class">
  <xsl:variable name="class-name">
    <xsl:call-template name="strip-beast-ns">
      <xsl:with-param name="name" select="compoundname"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="unqualified-class-name">
    <xsl:call-template name="strip-ns">
      <xsl:with-param name="name" select="compoundname"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="class-id">
    <xsl:call-template name="make-id">
      <xsl:with-param name="name" select="$class-name"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="class-file" select="location/@file"/>
  <xsl:text>[section:</xsl:text>
  <xsl:value-of select="$class-id"/>
  <xsl:text> </xsl:text>
  <xsl:value-of select="$class-name"/>
  <xsl:text>]&#xd;</xsl:text>
  <xsl:apply-templates select="briefdescription" mode="markup"/>
  <xsl:text>&#xd;```&#xd;</xsl:text>
  <xsl:apply-templates select="templateparamlist" mode="class-detail"/>
  <xsl:value-of select="@kind"/>
  <xsl:text> </xsl:text>
  <xsl:value-of select="$unqualified-class-name"/>
  <xsl:if test="count(basecompoundref[not(contains(.,'::detail'))]) > 0">
    <xsl:text> :</xsl:text>
  </xsl:if>
  <xsl:text>&#xd;</xsl:text>
  <xsl:for-each select="basecompoundref[not(contains(.,'::detail'))]">
    <xsl:text>    </xsl:text>
    <xsl:if test="@prot='public'">
      <xsl:text>public </xsl:text>
    </xsl:if>
    <xsl:call-template name="strip-beast-ns">
      <xsl:with-param name="name" select="."/>
    </xsl:call-template>
    <xsl:if test="not(position() = last())">
      <xsl:text>,</xsl:text>
    </xsl:if>
    <xsl:text>&#xd;</xsl:text>
  </xsl:for-each>
  <xsl:text>```&#xd;</xsl:text>
  <xsl:call-template name="class-tables">
    <xsl:with-param name="class-name" select="$class-name"/>
    <xsl:with-param name="class-id" select="$class-id"/>
  </xsl:call-template>
  <xsl:apply-templates select="detaileddescription" mode="markup"/>
  <xsl:call-template name="header-requirements">
    <xsl:with-param name="file" select="$class-file"/>
  </xsl:call-template>
  <xsl:call-template name="class-members">
    <xsl:with-param name="class-name" select="$class-name"/>
    <xsl:with-param name="class-id" select="$class-id"/>
    <xsl:with-param name="class-file" select="$class-file"/>
  </xsl:call-template>
<xsl:text>[endsect]&#xd;&#xd;&#xd;&#xd;</xsl:text>
</xsl:template>

<xsl:template name="class-tables">
  <xsl:param name="class-name"/>
  <xsl:param name="class-id"/>
  <xsl:if test="
      count(
        sectiondef[@kind='public-type'] |
        innerclass[@prot='public' and not(contains(., '_handler'))]) &gt; 0">
    <xsl:text>[heading Types]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="
        sectiondef[@kind='public-type']/memberdef |
        innerclass[@prot='public' and not(contains(., '_handler'))]" mode="class-table">
      <xsl:sort select="concat(name,  (.)[not(name)])"/>
      <xsl:text>  [&#xd;</xsl:text>
      <xsl:choose>
        <xsl:when test="count(name) &gt; 0">
          <xsl:text>    [[link beast.ref.</xsl:text>
          <xsl:value-of select="$class-id"/>
          <xsl:text>.</xsl:text>
          <xsl:value-of select="name"/>
          <xsl:text> [*</xsl:text>
          <xsl:value-of select="name"/>
          <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
          <xsl:call-template name="escape-name">
            <xsl:with-param name="text" select="briefdescription"/>
          </xsl:call-template>
          <xsl:text>&#xd;    ]&#xd;</xsl:text>
        </xsl:when>
        <xsl:otherwise>
          <xsl:variable name="type-name">
            <xsl:call-template name="strip-beast-ns">
              <xsl:with-param name="name" select="."/>
            </xsl:call-template>
          </xsl:variable>
          <xsl:variable name="unqualified-type-name">
            <xsl:call-template name="strip-ns">
              <xsl:with-param name="name" select="."/>
            </xsl:call-template>
          </xsl:variable>
          <xsl:variable name="type-id">
            <xsl:call-template name="make-id">
              <xsl:with-param name="name" select="$type-name"/>
            </xsl:call-template>
          </xsl:variable>
          <xsl:variable name="type-ref-id" select="@refid"/>
          <xsl:text>    [[link beast.ref.</xsl:text>
          <xsl:value-of select="$type-id"/>
          <xsl:text> [*</xsl:text>
          <xsl:value-of select="$unqualified-type-name"/>
          <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
          <xsl:value-of select="(/doxygen//compounddef[@id=$type-ref-id])[1]/briefdescription"/>
          <xsl:text>&#xd;    ]&#xd;</xsl:text>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:text>  ]&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='public-func' or @kind='public-static-func']) > 0">
    <xsl:text>[heading Member Functions]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='public-func' or @kind='public-static-func']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:variable name="name">
        <xsl:value-of select="name"/>
      </xsl:variable>
      <xsl:variable name="escaped-name">
        <xsl:call-template name="escape-name">
          <xsl:with-param name="text" select="$name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="doxygen-id">
        <xsl:value-of select="@id"/>
      </xsl:variable>
      <xsl:variable name="overload-count">
        <xsl:value-of select="count(../memberdef[name = $name])"/>
      </xsl:variable>
      <xsl:variable name="overload-position">
        <xsl:for-each select="../memberdef[name = $name]">
          <xsl:if test="@id = $doxygen-id">
            <xsl:value-of select="position()"/>
          </xsl:if>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="$overload-position = 1">
        <xsl:text>  [&#xd;</xsl:text>
        <xsl:text>    [[link beast.ref.</xsl:text>
        <xsl:value-of select="$class-id"/>.<xsl:value-of select="$id"/>
        <xsl:text> [*</xsl:text>
        <xsl:value-of select="$escaped-name"/>
        <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="not($overload-position = 1) and not(briefdescription = preceding-sibling::*/briefdescription)">
        <xsl:text>&#xd;&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="$overload-position = $overload-count">
        <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
      </xsl:if>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='protected-func' or @kind='protected-static-func']) > 0">
    <xsl:text>[heading Protected Member Functions]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='protected-func' or @kind='protected-static-func']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:variable name="name">
        <xsl:value-of select="name"/>
      </xsl:variable>
      <xsl:variable name="id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="doxygen-id">
        <xsl:value-of select="@id"/>
      </xsl:variable>
      <xsl:variable name="overload-count">
        <xsl:value-of select="count(../memberdef[name = $name])"/>
      </xsl:variable>
      <xsl:variable name="overload-position">
        <xsl:for-each select="../memberdef[name = $name]">
          <xsl:if test="@id = $doxygen-id">
            <xsl:value-of select="position()"/>
          </xsl:if>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="$overload-position = 1">
        <xsl:text>  [&#xd;</xsl:text>
        <xsl:text>    [[link beast.ref.</xsl:text>
        <xsl:value-of select="$class-id"/>.<xsl:value-of select="$id"/>
        <xsl:text> [*</xsl:text>
        <xsl:value-of select="$name"/>
        <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="not($overload-position = 1) and not(briefdescription = preceding-sibling::*/briefdescription)">
        <xsl:text>&#xd;&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="$overload-position = $overload-count">
        <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
      </xsl:if>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='private-func' or @kind='protected-private-func']) > 0">
    <xsl:text>[heading Private Member Functions]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='private-func']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:variable name="name">
        <xsl:value-of select="name"/>
      </xsl:variable>
      <xsl:variable name="id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="doxygen-id">
        <xsl:value-of select="@id"/>
      </xsl:variable>
      <xsl:variable name="overload-count">
        <xsl:value-of select="count(../memberdef[name = $name])"/>
      </xsl:variable>
      <xsl:variable name="overload-position">
        <xsl:for-each select="../memberdef[name = $name]">
          <xsl:if test="@id = $doxygen-id">
            <xsl:value-of select="position()"/>
          </xsl:if>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="$overload-position = 1">
        <xsl:text>  [&#xd;</xsl:text>
        <xsl:text>    [[link beast.ref.</xsl:text>
        <xsl:value-of select="$class-id"/>.<xsl:value-of select="$id"/>
        <xsl:text> [*</xsl:text>
        <xsl:value-of select="$name"/>
        <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="not($overload-position = 1) and not(briefdescription = preceding-sibling::*/briefdescription)">
        <xsl:text>&#xd;&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="$overload-position = $overload-count">
        <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
      </xsl:if>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='public-attrib' or @kind='public-static-attrib']) > 0">
    <xsl:text>[heading Data Members]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='public-attrib' or @kind='public-static-attrib']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:text>  [&#xd;</xsl:text>
      <xsl:text>    [[link beast.ref.</xsl:text>
      <xsl:value-of select="$class-id"/>.<xsl:value-of select="name"/>
      <xsl:text> [*</xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
      <xsl:value-of select="briefdescription"/>
      <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='protected-attrib' or @kind='protected-static-attrib']) > 0">
    <xsl:text>[heading Protected Data Members]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='protected-attrib' or @kind='protected-static-attrib']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:text>  [&#xd;</xsl:text>
      <xsl:text>    [[link beast.ref.</xsl:text>
      <xsl:value-of select="$class-id"/>.<xsl:value-of select="name"/>
      <xsl:text> [*</xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
      <xsl:value-of select="briefdescription"/>
      <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='private-attrib' or @kind='private-static-attrib']) > 0">
    <xsl:text>[heading Private Data Members]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='private-attrib' or @kind='private-static-attrib']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:text>  [&#xd;</xsl:text>
      <xsl:text>    [[link beast.ref.</xsl:text>
      <xsl:value-of select="$class-id"/>.<xsl:value-of select="name"/>
      <xsl:text> [*</xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
      <xsl:value-of select="briefdescription"/>
      <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='friend']/memberdef[not(type = 'friend class') and not(contains(name, '_helper'))]) &gt; 0">
    <xsl:text>[heading Friends]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='friend']/memberdef[not(type = 'friend class') and not(contains(name, '_helper'))]" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:variable name="name">
        <xsl:value-of select="name"/>
      </xsl:variable>
      <xsl:variable name="id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="doxygen-id">
        <xsl:value-of select="@id"/>
      </xsl:variable>
      <xsl:variable name="overload-count">
        <xsl:value-of select="count(../memberdef[name = $name])"/>
      </xsl:variable>
      <xsl:variable name="overload-position">
        <xsl:for-each select="../memberdef[name = $name]">
          <xsl:if test="@id = $doxygen-id">
            <xsl:value-of select="position()"/>
          </xsl:if>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="$overload-position = 1">
        <xsl:text>  [&#xd;</xsl:text>
        <xsl:text>    [[link beast.ref.</xsl:text>
        <xsl:value-of select="$class-id"/>.<xsl:value-of select="$id"/>
        <xsl:text> [*</xsl:text>
        <xsl:value-of select="$name"/>
        <xsl:text>]]]&#xd;    [&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="not($overload-position = 1) and not(briefdescription = preceding-sibling::*/briefdescription)">
        <xsl:text>&#xd;&#xd;      </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="$overload-position = $overload-count">
        <xsl:text>&#xd;    ]&#xd;  ]&#xd;</xsl:text>
      </xsl:if>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:if test="count(sectiondef[@kind='related']/memberdef) &gt; 0">
    <xsl:text>[heading Related Functions]&#xd;</xsl:text>
    <xsl:text>[table&#xd;  [[Name][Description]]&#xd;</xsl:text>
    <xsl:for-each select="sectiondef[@kind='related']/memberdef" mode="class-table">
      <xsl:sort select="name"/>
      <xsl:variable name="name">
        <xsl:value-of select="name"/>
      </xsl:variable>
      <xsl:variable name="id">
        <xsl:call-template name="make-id">
          <xsl:with-param name="name" select="$name"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="doxygen-id">
        <xsl:value-of select="@id"/>
      </xsl:variable>
      <xsl:variable name="overload-count">
        <xsl:value-of select="count(../memberdef[name = $name])"/>
      </xsl:variable>
      <xsl:variable name="overload-position">
        <xsl:for-each select="../memberdef[name = $name]">
          <xsl:if test="@id = $doxygen-id">
            <xsl:value-of select="position()"/>
          </xsl:if>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="$overload-position = 1">
      [
        [[link beast.ref.<xsl:value-of select="$class-id"/>.<xsl:value-of select="$id"/>
          <xsl:text> </xsl:text>[*<xsl:value-of select="$name"/><xsl:text>]]]
        [</xsl:text><xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="not($overload-position = 1) and not(briefdescription = preceding-sibling::*/briefdescription)">
        <xsl:value-of select="$newline"/>
        <xsl:value-of select="$newline"/>
        <xsl:text>     </xsl:text>
        <xsl:value-of select="briefdescription"/>
      </xsl:if>
      <xsl:if test="$overload-position = $overload-count">
        <xsl:text>]
      ]
        </xsl:text>
      </xsl:if>
    </xsl:for-each>
    ]
  </xsl:if>
</xsl:template>



<xsl:template name="class-members">
<xsl:param name="class-name"/>
<xsl:param name="class-id"/>
<xsl:param name="class-file"/>
<xsl:apply-templates select="sectiondef[@kind='public-type' or @kind='public-func' or @kind='public-static-func' or @kind='public-attrib' or @kind='public-static-attrib' or @kind='protected-func' or @kind='protected-static-func' or @kind='protected-attrib' or @kind='protected-static-attrib' or @kind='friend' or @kind='related']/memberdef[not(type = 'friend class') and not(contains(name, '_helper'))]" mode="class-detail">
  <xsl:sort select="name"/>
  <xsl:with-param name="class-name" select="$class-name"/>
  <xsl:with-param name="class-id" select="$class-id"/>
  <xsl:with-param name="class-file" select="$class-file"/>
</xsl:apply-templates>
<xsl:if test="$class-name = 'io_service::service'">
  <xsl:apply-templates select="sectiondef[@kind='private-func']/memberdef[not(type = 'friend class') and not(contains(name, '_helper'))]" mode="class-detail">
    <xsl:sort select="name"/>
    <xsl:with-param name="class-name" select="$class-name"/>
    <xsl:with-param name="class-id" select="$class-id"/>
    <xsl:with-param name="class-file" select="$class-file"/>
  </xsl:apply-templates>
</xsl:if>
</xsl:template>



<!-- Class detail -->

<xsl:template match="memberdef" mode="class-detail">
  <xsl:param name="class-name"/>
  <xsl:param name="class-id"/>
  <xsl:param name="class-file"/>
  <xsl:variable name="name">
    <xsl:value-of select="name"/>
  </xsl:variable>
  <xsl:variable name="escaped-name">
    <xsl:call-template name="escape-name">
      <xsl:with-param name="text" select="$name"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="id">
    <xsl:call-template name="make-id">
      <xsl:with-param name="name" select="$name"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="doxygen-id">
    <xsl:value-of select="@id"/>
  </xsl:variable>
  <xsl:variable name="overload-count">
    <xsl:value-of select="count(../memberdef[name = $name])"/>
  </xsl:variable>
  <xsl:variable name="overload-position">
    <xsl:for-each select="../memberdef[name = $name]">
      <xsl:if test="@id = $doxygen-id">
        <xsl:value-of select="position()"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>
  <xsl:if test="$overload-count &gt; 1 and $overload-position = 1">
    <xsl:text>[section:</xsl:text>
    <xsl:value-of select="$id"/>
    <xsl:text> </xsl:text>
    <xsl:value-of select="$class-name"/>
    <xsl:text>::</xsl:text>
    <xsl:value-of select="$escaped-name"/>
    <xsl:text>]&#xd;</xsl:text>
    <xsl:text>[indexterm2 </xsl:text>
    <xsl:value-of select="$escaped-name"/>
    <xsl:text>..</xsl:text>
    <xsl:value-of select="$class-name"/>
    <xsl:text>]&#xd;</xsl:text>
    <xsl:apply-templates select="briefdescription" mode="markup"/>
    <xsl:text>```&#xd;</xsl:text>
    <xsl:for-each select="../memberdef[name = $name]">
      <xsl:if test="position() &gt; 1">
        <xsl:text>&#xd;</xsl:text>
        <xsl:if test=" not(briefdescription = preceding-sibling::*/briefdescription)">
          <xsl:text>```&#xd;</xsl:text>
          <xsl:apply-templates select="briefdescription" mode="markup"/>
          <xsl:text>```&#xd;</xsl:text>
        </xsl:if>
      </xsl:if>
      <xsl:apply-templates select="templateparamlist" mode="class-detail"/>
      <xsl:if test="@explicit='yes'">explicit&#xd;</xsl:if>
      <xsl:if test="@friend='yes'">friend&#xd;</xsl:if>
      <xsl:if test="@static='yes'">static&#xd;</xsl:if>
      <xsl:if test="@virt='virtual'">virtual&#xd;</xsl:if>
      <xsl:variable name="stripped-type">
        <xsl:call-template name="cleanup-type">
          <xsl:with-param name="name" select="type"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:if test="string-length($stripped-type) &gt; 0">
        <xsl:value-of select="$stripped-type"/><xsl:text> </xsl:text>
      </xsl:if>
      <xsl:text>``[link beast.ref.</xsl:text>
      <xsl:value-of select="$class-id"/>
      <xsl:text>.</xsl:text>
      <xsl:value-of select="$id"/>
      <xsl:text>.overload</xsl:text>
      <xsl:value-of select="position()"/>
      <xsl:text> </xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>]``(</xsl:text>
      <xsl:apply-templates select="param" mode="class-detail"/>
      <xsl:text>)</xsl:text>
      <xsl:if test="@const='yes'">
        <xsl:text> const</xsl:text>
      </xsl:if>
      <xsl:text>;&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>```&#xd;</xsl:text>
  </xsl:if>

<!-- Member function detail -->

  <xsl:text>[section:</xsl:text>
  <xsl:if test="$overload-count = 1">
    <xsl:value-of select="$id"/>
  </xsl:if>
  <xsl:if test="$overload-count &gt; 1">
    <xsl:text>overload</xsl:text>
    <xsl:value-of select="$overload-position"/>
  </xsl:if>
  <xsl:text> </xsl:text>
  <xsl:value-of select="$class-name"/>
    <xsl:text>::</xsl:text>
    <xsl:value-of select="$escaped-name"/>
    <xsl:if test="$overload-count &gt; 1">
    <xsl:text> (</xsl:text>
    <xsl:value-of select="$overload-position"/>
    <xsl:text> of </xsl:text>
    <xsl:value-of select="$overload-count"/>
    <xsl:text> overloads)</xsl:text>
  </xsl:if>
  <xsl:text>]&#xd;</xsl:text>
  <xsl:if test="not(starts-with($doxygen-id, ../../@id))">
    <xsl:variable name="inherited-from" select="/doxygen/compounddef[starts-with($doxygen-id, @id)]/compoundname"/>
    <xsl:if test="not(contains($inherited-from, '::detail'))">
      <xsl:text>['Inherited from </xsl:text>
      <xsl:call-template name="strip-beast-ns">
        <xsl:with-param name="name" select="$inherited-from"/>
      </xsl:call-template>
      <xsl:text>.]&#xd;</xsl:text>
    </xsl:if>
  </xsl:if>
  <xsl:if test="$overload-count = 1">
    <xsl:text>[indexterm2 </xsl:text>
    <xsl:value-of select="$escaped-name"/>
    <xsl:text>..</xsl:text>
    <xsl:value-of select="$class-name"/>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:apply-templates select="briefdescription" mode="markup"/>
  <xsl:choose>
    <xsl:when test="@kind='typedef'">
      <xsl:call-template name="typedef" mode="class-detail">
        <xsl:with-param name="class-name" select="$class-name"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="@kind='variable'">
      <xsl:call-template name="variable" mode="class-detail"/>
    </xsl:when>
    <xsl:when test="@kind='enum'">
      <xsl:call-template name="enum" mode="class-detail">
        <xsl:with-param name="enum-name" select="$class-name"/>
      </xsl:call-template>
    </xsl:when>
    <xsl:when test="@kind='function'">
      <xsl:text>```&#xd;</xsl:text>
      <xsl:call-template name="function" mode="class-detail"/>
      <xsl:text>```&#xd;</xsl:text>
    </xsl:when>
    <xsl:when test="@kind='friend'">
      <xsl:text>```&#xd;</xsl:text>
      <xsl:call-template name="function" mode="class-detail"/>
      <xsl:text>```&#xd;</xsl:text>
    </xsl:when>
  </xsl:choose>
  <xsl:apply-templates select="detaileddescription"/>
  <xsl:if test="@kind='typedef' or @kind='friend'">
    <xsl:call-template name="header-requirements">
      <xsl:with-param name="file" select="$class-file"/>
    </xsl:call-template>
  </xsl:if>
  <xsl:choose>
    <xsl:when test="$overload-count &gt; 1 and $overload-position = $overload-count">
      <xsl:text>[endsect]&#xd;[endsect]&#xd;&#xd;&#xd;&#xd;</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:text>[endsect]&#xd;</xsl:text>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>



<xsl:template name="typedef">
  <xsl:param name="class-name"/>
  <xsl:text>```&#xd;using </xsl:text>
  <xsl:value-of select="name"/>
  <xsl:text> = </xsl:text>
  <xsl:variable name="stripped-type">
    <xsl:call-template name="cleanup-type">
      <xsl:with-param name="name" select="type"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:if test="string-length($stripped-type) &gt; 0">
    <xsl:value-of select="$stripped-type"/>
  </xsl:if>
  <xsl:text>;&#xd;```&#xd;</xsl:text>
  <xsl:if test="count(type/ref) &gt; 0 and not(contains(type, '*'))">
    <xsl:variable name="class-refid">
      <xsl:for-each select="type/ref[1]">
        <xsl:value-of select="@refid"/>
      </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="name" select="name"/>
    <xsl:for-each select="/doxygen/compounddef[@id=$class-refid]">
      <xsl:call-template name="class-tables">
        <xsl:with-param name="class-name">
          <xsl:value-of select="concat($class-name, '::', $name)"/>
        </xsl:with-param>
        <xsl:with-param name="class-id">
          <xsl:call-template name="make-id">
            <xsl:with-param name="name">
              <xsl:call-template name="strip-beast-ns">
                <xsl:with-param name="name" select="compoundname"/>
              </xsl:call-template>
            </xsl:with-param>
          </xsl:call-template>
        </xsl:with-param>
      </xsl:call-template>
      <xsl:apply-templates select="detaileddescription" mode="markup"/>
    </xsl:for-each>
  </xsl:if>
</xsl:template>



<xsl:template name="variable">
  <xsl:text>```&#xd;</xsl:text>
  <xsl:if test="@static='yes'">
    <xsl:text>static&#xd;</xsl:text>
  </xsl:if>
  <xsl:value-of select="type"/>
  <xsl:text> </xsl:text>
  <xsl:value-of select="name"/>
  <xsl:if test="count(initializer) = 1">
    <xsl:text> </xsl:text>
    <xsl:value-of select="initializer"/>
  </xsl:if>
  <xsl:text>;&#xd;```&#xd;</xsl:text>
</xsl:template>



<xsl:template name="enum">
  <xsl:param name="enum-name"/>
  <xsl:text>```&#xd;</xsl:text>
  <xsl:text>enum </xsl:text>
  <xsl:value-of select="name"/>
  <xsl:text>&#xd;```&#xd;</xsl:text>
  <xsl:if test="count(enumvalue) &gt; 0">
    <xsl:text>&#xd;</xsl:text>
    <xsl:for-each select="enumvalue">
      <xsl:text>[indexterm2 </xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>..</xsl:text>
      <xsl:value-of select="$enum-name"/>
      <xsl:text>]</xsl:text>
      <xsl:text>&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>[heading Values]&#xd;</xsl:text>
    <xsl:text>[variablelist&#xd;</xsl:text>
    <xsl:for-each select="enumvalue">
      <xsl:text>  [[</xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>]&#xd;   [</xsl:text>
      <xsl:value-of select="briefdescription"/>
      <xsl:text>]]&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
</xsl:template>



<xsl:template name="function">
  <xsl:variable name="doxygen-id">
    <xsl:value-of select="@id"/>
  </xsl:variable>
  <xsl:choose>
    <xsl:when test="count(/doxygen//memberdef[@id=$doxygen-id]/templateparamlist) = 1">
      <xsl:apply-templates select="/doxygen//memberdef[@id=$doxygen-id]/templateparamlist" mode="class-detail"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:apply-templates select="templateparamlist" mode="class-detail"/>
    </xsl:otherwise>
  </xsl:choose>
  <xsl:variable name="stripped-type">
    <xsl:call-template name="cleanup-type">
      <xsl:with-param name="name" select="type"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:if test="@static='yes'">static&#xd;</xsl:if>
  <xsl:if test="@virt='virtual'">virtual&#xd;</xsl:if>
  <xsl:if test="string-length($stripped-type) &gt; 0">
    <xsl:value-of select="$stripped-type"/>
    <xsl:text>&#xd;</xsl:text>
  </xsl:if>
  <xsl:value-of select="name"/>
  <xsl:text>(</xsl:text>
  <xsl:apply-templates select="param" mode="class-detail"/>
  <xsl:text>)</xsl:text>
  <xsl:if test="@const='yes'"> const</xsl:if>
  <xsl:text>;&#xd;</xsl:text>
</xsl:template>


<xsl:template match="templateparamlist" mode="class-detail">
  <xsl:text>template&lt;&#xd;</xsl:text>
  <xsl:apply-templates select="param" mode="class-detail-template"/>
  <xsl:text>&gt;&#xd;</xsl:text>
</xsl:template>

<xsl:template match="param" mode="class-detail-template">
  <xsl:text>    </xsl:text>
  <xsl:value-of select="type"/>
  <xsl:choose>
    <xsl:when test="declname = 'Allocator'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Arg'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'BufferSequence'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'ByteType'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Clock'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'CompletionCondition'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'ConnectCondition'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Context_Service'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'DatagramSocketService1'">
      <xsl:value-of select="concat('``[link beast.ref.DatagramSocketService ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'EndpointIterator'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Elem'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'ErrorEnum'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Function'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Iterator'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'MatchCondition'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'N'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'OtherAllocator'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'PasswordCallback'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'PodType'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'PointerToPodType'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Protocol1'">
      <xsl:value-of select="concat('``[link beast.ref.Protocol ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'RawSocketService1'">
      <xsl:value-of select="concat('``[link beast.ref.RawSocketService ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'SeqPacketSocketService1'">
      <xsl:value-of select="concat('``[link beast.ref.SeqPacketSocketService ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'Signature'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'SocketAcceptorService1' or declname = 'SocketAcceptorService2'">
      <xsl:value-of select="concat('``[link beast.ref.SocketAcceptorService ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'SocketService1' or declname = 'SocketService2'">
      <xsl:value-of select="concat('``[link beast.ref.SocketService ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'Stream'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'StreamSocketService1'">
      <xsl:value-of select="concat('``[link beast.ref.StreamSocketService ', declname, ']``')"/>
    </xsl:when>
    <xsl:when test="declname = 'T'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'T1'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'TN'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Time'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'TimeType'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'Traits'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="declname = 'VerifyCallback'">
      <xsl:value-of select="declname"/>
    </xsl:when>
    <xsl:when test="count(declname) = 0">
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="concat(' ``[link beast.ref.', declname, ' ', declname, ']``')"/>
    </xsl:otherwise>
  </xsl:choose>
  <xsl:if test="count(defval) > 0">
    <xsl:text> = </xsl:text>
    <xsl:value-of select="defval"/>
  </xsl:if>
  <xsl:if test="not(position() = last())">
    <xsl:text>,&#xd;</xsl:text>
  </xsl:if>
</xsl:template>

<xsl:template match="param" mode="class-detail">
  <xsl:text>&#xd;    </xsl:text>
  <xsl:choose>
    <xsl:when test="string-length(array) &gt; 0">
      <xsl:value-of select="substring-before(type, '&amp;')"/>
      <xsl:text>(&amp;</xsl:text>
      <xsl:value-of select="declname"/>
      <xsl:text>)</xsl:text>
      <xsl:value-of select="array"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:choose>
        <xsl:when test="' &amp;' = substring(type, string-length(type) - 1)">
          <xsl:value-of select="substring(type, 1, string-length(type) - 2)"/>
          <xsl:text>&amp;</xsl:text>
        </xsl:when>
        <xsl:when test="' *' = substring(type, string-length(type) - 1)">
          <xsl:value-of select="substring(type, 1, string-length(type) - 2)"/>
          <xsl:text>*</xsl:text>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="type"/>
        </xsl:otherwise>
      </xsl:choose>
      <xsl:text> </xsl:text>
      <xsl:value-of select="declname"/>
    </xsl:otherwise>
  </xsl:choose>
  <xsl:if test="count(defval) > 0"> = <xsl:value-of select="defval"/></xsl:if>
  <xsl:if test="not(position() = last())">
    <xsl:text>,</xsl:text>
  </xsl:if>
</xsl:template>

<xsl:template match="*" mode="class-detail"/>

<!--========== Namespace ==========-->

<xsl:template name="namespace-memberdef">
  <xsl:variable name="name">
    <xsl:call-template name="strip-beast-ns">
      <xsl:with-param name="name" select="concat(../../compoundname, '::', name)"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="unqualified-name">
    <xsl:call-template name="strip-ns">
      <xsl:with-param name="name" select="$name"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="id">
    <xsl:call-template name="make-id">
      <xsl:with-param name="name" select="$name"/>
    </xsl:call-template>
  </xsl:variable>
  <xsl:variable name="doxygen-id">
    <xsl:value-of select="@id"/>
  </xsl:variable>
  <xsl:variable name="overload-count">
    <xsl:value-of select="count(../memberdef[name = $unqualified-name])"/>
  </xsl:variable>
  <xsl:variable name="overload-position">
    <xsl:for-each select="../memberdef[name = $unqualified-name]">
      <xsl:if test="@id = $doxygen-id">
        <xsl:value-of select="position()"/>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>
  <xsl:if test="$overload-count &gt; 1 and $overload-position = 1">
    <xsl:text>[section:</xsl:text>
    <xsl:value-of select="$id"/>
    <xsl:text> </xsl:text>
    <xsl:value-of select="$name"/>
    <xsl:text>]&#xd;</xsl:text>
    <xsl:text>[indexterm1 </xsl:text>
    <xsl:value-of select="$name"/>
    <xsl:text>]</xsl:text>
    <xsl:choose>
      <xsl:when test="count(/doxygen/compounddef[@kind='group' and compoundname=$name]) &gt; 0">
        <xsl:for-each select="/doxygen/compounddef[@kind='group' and compoundname=$name]">
          <xsl:apply-templates select="briefdescription" mode="markup"/>
        </xsl:for-each>
      </xsl:when>
      <xsl:otherwise>
        <xsl:apply-templates select="briefdescription" mode="markup"/>
      </xsl:otherwise>
    </xsl:choose>
    <xsl:text>```&#xd;</xsl:text>
    <xsl:for-each select="../memberdef[name = $unqualified-name]">
      <xsl:variable name="stripped-type">
        <xsl:call-template name="cleanup-type">
          <xsl:with-param name="name" select="type"/>
        </xsl:call-template>
      </xsl:variable>
      <xsl:apply-templates select="templateparamlist" mode="class-detail"/>
      <xsl:if test="string-length($stripped-type) &gt; 0">
        <xsl:value-of select="$stripped-type"/>
        <xsl:text>&#xd;</xsl:text>
      </xsl:if>
      <xsl:text>``[link beast.ref.</xsl:text>
      <xsl:value-of select="$id"/>
      <xsl:text>.overload</xsl:text>
      <xsl:value-of select="position()"/>
      <xsl:text> </xsl:text>
      <xsl:value-of select="name"/>
      <xsl:text>]``(</xsl:text>
      <xsl:apply-templates select="param" mode="class-detail"/>
      <xsl:text>);&#xd;&#xd;</xsl:text>
    </xsl:for-each>
    <xsl:text>```&#xd;</xsl:text>
    <xsl:for-each select="/doxygen/compounddef[@kind='group' and compoundname=$name]">
      <xsl:apply-templates select="detaileddescription" mode="markup"/>
    </xsl:for-each>
    <xsl:call-template name="header-requirements">
      <xsl:with-param name="file" select="location/@file"/>
    </xsl:call-template>
  </xsl:if>
  <xsl:if test="$overload-count = 1">
    <xsl:text>[section:</xsl:text>
    <xsl:value-of select="$id"/>
  </xsl:if>
  <xsl:if test="$overload-count &gt; 1">
    <xsl:text>[section:</xsl:text>
    <xsl:text>overload</xsl:text>
    <xsl:value-of select="$overload-position"/>
  </xsl:if>
  <xsl:text> </xsl:text>
  <xsl:value-of select="$name"/>
  <xsl:if test="$overload-count &gt; 1">
    <xsl:text> (</xsl:text>
    <xsl:value-of select="$overload-position"/>
    <xsl:text> of </xsl:text>
    <xsl:value-of select="$overload-count"/>
    <xsl:text> overloads)</xsl:text>
  </xsl:if>
  <xsl:text>]&#xd;</xsl:text>
  <xsl:if test="$overload-count = 1">
    <xsl:text>[indexterm1 </xsl:text>
    <xsl:value-of select="$name"/>
    <xsl:text>]&#xd;</xsl:text>
  </xsl:if>
  <xsl:apply-templates select="briefdescription" mode="markup"/>
    <xsl:choose>
      <xsl:when test="@kind='typedef'">
        <xsl:call-template name="typedef">
          <xsl:with-param name="class-name" select="$name"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:when test="@kind='variable'">
        <xsl:call-template name="variable"/>
      </xsl:when>
      <xsl:when test="@kind='enum'">
        <xsl:call-template name="enum">
          <xsl:with-param name="enum-name" select="$name"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:when test="@kind='function'">
        <xsl:text>&#xd;```&#xd;</xsl:text>
        <xsl:call-template name="function"/>
        <xsl:text>&#xd;```&#xd;</xsl:text>
      </xsl:when>
    </xsl:choose>
  <xsl:apply-templates select="detaileddescription" mode="markup"/>
  <xsl:if test="$overload-count = 1">
    <xsl:call-template name="header-requirements">
      <xsl:with-param name="file" select="location/@file"/>
    </xsl:call-template>
  </xsl:if>
  <xsl:choose>
    <xsl:when test="$overload-count &gt; 1 and $overload-position = $overload-count">
      <xsl:text>[endsect]&#xd;[endsect]&#xd;&#xd;&#xd;&#xd;</xsl:text>
    </xsl:when>
    <xsl:otherwise>
      <xsl:text>[endsect]&#xd;</xsl:text>
    </xsl:otherwise>
  </xsl:choose>
</xsl:template>

</xsl:stylesheet>
