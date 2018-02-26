
/**************************************************************************
 * FPorterStemmer.d - 29-Mai-2007
 * - Filter for perferming word stemming based on the Porter algorithm
 *
 * Copyright (c) 2007 Daniel Truemper (daniel-truemper at gmx.de)
 *
 **************************************************************************/

/**
 * Note:
 *
 * This implementation was converted from the python implementation
 * made by Vivake Gupta (v@nano.com) so all credit belongs to him!
 *
 * ---- original comment
 *
 * This is the Porter stemming algorithm, ported to Python from the
 * version coded up in ANSI C by the author. It may be be regarded
 * as canonical, in that it follows the algorithm presented in
 *
 * Porter, 1980, An algorithm for suffix stripping, Program, Vol. 14,
 * no. 3, pp 130-137,
 *
 * only differing from it at the points maked --DEPARTURE-- below.
 *
 * See also http://www.tartarus.org/~martin/PorterStemmer
 *
 * The algorithm as described in the paper could be exactly replicated
 * by adjusting the points of DEPARTURE, but this is barely necessary,
 * because (a) the points of DEPARTURE are definitely improvements, and
 * (b) no encoding of the Porter stemmer I have seen is anything like
 * as exact as this version, even with the points of DEPARTURE!
 *
 * Vivake Gupta (v@nano.com)
 *
 * Release 1: January 2001
 *
 * ---- end of original comment
 *
 */
module PorterStemmer;

public struct PorterStemmer
{
	private
	{
		const(char)[] m_b;			// buffer for the word
		int m_k = 0;
		int m_k0 = 0;
		int m_j = 0;		// offset within the string
	}

	/**
	 * cons returns true, if b[i] is a consonant
	 */
	private bool cons( int i )
	{
		if( m_b[i] == 'a' || m_b[i] == 'e' || m_b[i] == 'i' || m_b[i] == 'o' || m_b[i] == 'u' )
			return false;

		if( m_b[i] == 'y' )
		{
			if( i == m_k0 )
			{
				return true;
			} else
			{
				return !cons( i - 1 );
			}
		}
		return true;
	}

	/**
	 * measures the number of consonant sequences between k0 and j.
	 * if c is a consonant sequence and v a vowel sequence, and <..>
	 * indicates arbitrary presence,
	 *
	 * <c><v>       gives 0
	 * <c>vc<v>     gives 1
	 * <c>vcvc<v>   gives 2
	 * <c>vcvcvc<v> gives 3
	 *
	 */
	private int m()
	{
		int n = 0;
		int i = m_k0;
		
		while( true )
		{
			if( i > m_j )
			{
				return n;
			}
			if( !cons( i ) )
			{
				break;
			}
			i++;
		}
		i++;
		while( true )
		{
			while( true )
			{
				if( i > m_j )
				{
					return n;
				}
				if( cons( i ) )
				{
					break;
				}
				i++;
			}
			i++;
			n++;
			while( true )
			{
				if( i > m_j )
				{
					return n;
				}
				if( !cons( i ) )
				{
					break;
				}
				i++;
			}
			i++;
		}
	}

	/**
	 * returns true if k0...j contains a vowel
	 */
	private bool vowelinstem()
	{
		for( int i = m_k0; i < m_j + 1; i++ )
		{
			if( !cons( i ) )
				return true;
		}
		return false;
	}

	/**
	 * returns true if j, j-1 contains a double consonant
	 */
	private bool doublec( int j )
	{
		if( j < ( m_k0 + 1 ) )
			return false;
		if( m_b[j] != m_b[j-1] )
			return false;
		return cons( j );
	}

	/**
	 * is TRUE <=> i-2,i-1,i has the form consonant - vowel - consonant
	 * and also if the second c is not w,x or y. this is used when trying to
	 * restore an e at the end of a short  e.g.
	 *
	 *    cav(e), lov(e), hop(e), crim(e), but
	 *    snow, box, tray.
	 *
	 */
	private bool cvc( int i )
	{
		if( i < ( m_k0 + 2 ) || !cons( i ) || cons( i-1 ) || !cons( i-2 ) )
			return false;
		if( m_b[i] == 'w' || m_b[i] == 'x' || m_b[i] == 'y' )
			return false;
		return true;
	}

	/**
	 * ends(s) is TRUE <=> k0,...k ends with the string s.
	 */
	private bool ends( const char[] s )
	{
		int len = cast(int) s.length;

		if( s[ len - 1 ] != m_b[ m_k ] )
			return false;
		if( len > ( m_k - m_k0 + 1 ) )
			return false;

		int a = m_k - len + 1;
		int b = m_k + 1;

		if( m_b[a..b] != s )
		{
			return false;
		}
		m_j = m_k - len;

		return true;
	}

	/**
	 * setto(s) sets (j+1),...k to the characters in the string s, readjusting k.
	 */
	private void setto( const char[] s )
	{
		m_b = m_b[0..m_j+1] ~ s ~ m_b[ m_j + s.length + 1 .. m_b.length ];
		m_k = m_j + cast(int) s.length;
	}

	/**
	 * used further down
	 */
	private void r( const char[] s )
	{
		if( m() > 0 )
			setto( s );
	}

	/**
	 * step1ab() gets rid of plurals and -ed or -ing. e.g.
	 *
	 *     caresses  ->  caress
	 *     ponies    ->  poni
	 *     ties      ->  ti
	 *     caress    ->  caress
	 *     cats      ->  cat
	 *
	 *     feed      ->  feed
	 *     agreed    ->  agree
	 *     disabled  ->  disable
	 *
	 *     matting   ->  mat
	 *     mating    ->  mate
	 *     meeting   ->  meet
	 *     milling   ->  mill
	 *     messing   ->  mess
	 *
	 *     meetings  ->  meet
	 *
	 */
	private void step1ab()
	{
		if( m_b[ m_k ] == 's' )
		{
			if( ends( "sses" ) )
				m_k = m_k - 2;
			else if( ends( "ies" ) )
				setto( "i" );
			else if( m_b[ m_k - 1 ] != 's' )
				m_k--;
		}
		if( ends( "eed" ) )
		{
			if( m() > 0 )
				m_k--;
		} else if( ( ends( "ed" ) || ends( "ing" ) ) && vowelinstem() )
		{
			m_k = m_j;
			if( ends( "at" ) )
			{
				setto( "ate" );
			} else if( ends( "bl" ) )
			{
				setto( "ble" );
			} else if( ends( "iz" ) )
			{
				setto( "ize" );
			} else if( doublec( m_k ) )
			{
				m_k--;
				if( m_b[ m_k ] == 'l' || m_b[ m_k ] == 's' || m_b[ m_k ] == 'z' )
					m_k++;
			} else if( m() == 1 && cvc( m_k ) )
			{
				setto( "e" );
			}
		}
	}

	/**
	 * step1c() turns terminal y to i when there is another vowel in the stem.
	 */
	private void step1c()
	{
		if( ends( "y" ) && vowelinstem() )
		{
			m_b = m_b[0..m_k] ~ 'i' ~ m_b[ m_k+1 .. m_b.length ];
		}
	}

	/**
	 * step2() maps double suffices to single ones.
     * so -ization ( = -ize plus -ation) maps to -ize etc. note that the
     * string before the suffix must give m() > 0.*
	 */
	private void step2()
	{
		if( m_b[ m_k - 1 ] == 'a' )
		{
			if( ends( "ational" ) )
				r( "ate" );
			else if( ends( "tional" ) )
				r( "tion" );
		} else if( m_b[ m_k - 1 ] == 'c' )
		{
			if( ends( "enci" ) )
				r( "ence" );
			else if( ends( "anci" ) )
				r( "ance" );
		} else if( m_b[ m_k - 1 ] == 'e' )
		{
			if( ends( "izer" ) )
				r( "ize" );
		} else if( m_b[ m_k - 1 ] == 'l' )
		{
			if( ends( "bli" ) )
				r( "ble" );
			/* --DEPARTURE--
			 * To match the published algorithm, replace this phrase with
			 * if( ends( "abli" ) )
			 *	   r( "able" );
			 */
			else if( ends( "alli" ) )
				r( "al" );
			else if( ends( "entli" ) )
				r( "ent" );
			else if( ends( "eli" ) )
				r( "e" );
			else if( ends( "ousli" ) )
				r( "ous" );
		} else if( m_b[ m_k - 1 ] == 'o' )
		{
			if( ends( "ization" ) )
				r( "ize" );
			else if( ends( "ation" ) || ends( "ator" ) )
				r( "ate" );
		} else if( m_b[ m_k - 1 ] == 's' )
		{
			if( ends( "alism" ) )
				r( "al" );
			else if( ends( "iveness" ) )
				r( "ive" );
			else if( ends( "fulness" ) )
				r( "ful" );
			else if( ends( "ousness" ) )
				r( "ous" );
		} else if( m_b[ m_k - 1 ] == 't' )
		{
			if( ends( "aliti" ) )
				r( "al" );
			else if( ends( "iviti" ) )
				r( "ive" );
			else if( ends( "biliti" ) )
				r( "ble" );
		} else if( m_b[ m_k - 1 ] == 'g' )
		{
			/**
			 * --DEPARTURE--
			 * To match the published algorithm, delete this phrase
			 */
			if( ends( "logi" ) )
				r( "log" );
		}

	}

	/**
	 * step3() dels with -ic-, -full, -ness etc. similar strategy to step2.
	 */
	private void step3()
	{
		if( m_b[ m_k ] == 'e' )
		{
			if( ends( "icate" ) )
				r( "ic" );
			else if( ends( "ative" ) )
				r( "" );
			else if( ends( "alize" ) )
				r( "al" );
		}else if( m_b[ m_k ] == 'i' )
		{
			if( ends( "iciti" ) )
				r( "ic" );
		}else if( m_b[ m_k ] == 'l' )
		{
			if( ends( "ical" ) )
				r( "ic" );
			else if( ends( "ful" ) )
				r( "" );
		}else if( m_b[ m_k ] == 's' )
		{
			if( ends( "ness" ) )
				r( "" );
		}
	}

	/**
	 * step4() takes off -ant, -ence etc., in context <c>vcvc<v>.
	 */
	private void step4()
	{

		/* fixes bug 1 */
		if( m_k == 0 )
			return;
		switch( m_b[ m_k - 1 ] )
		{

			case 'a':
				if( ends( "al" ) )
					break;
				return;

			case 'c':
				if( ends( "ance" ) || ends( "ence" ) )
					break;
				return;

			case 'e':
				if( ends( "er" ) )
					break;
				return;

			case 'i':
				if( ends( "ic" ) )
					break;
				return;
				
			case 'l':
				if( ends( "able" ) || ends( "ible" ) )
					break;
				return;

			case 'n':
				if( ends( "ant" ) || ends( "ement" ) || ends( "ment" ) || ends( "ent" ) )
					break;
				return;

			case 'o':
				if( ends( "ion" ) && m_j >= 0 && ( m_b[ m_j ] == 's' || m_b[ m_j ] == 't' ) )
				{
								  /* m_j >= 0 fixes bug 2 */
					break;
				}
				if( ends( "ou" ) )
					break;
				return;

			case 's':
				if( ends( "ism" ) )
					break;
				return;

			case 't':
				if( ends( "ate" ) || ends( "iti" ) )
					break;
				return;

			case 'u':
				if( ends( "ous" ) )
					break;
				return;
			
			case 'v':
				if( ends( "ive" ) )
					break;
				return;

			case 'z':
				if( ends( "ize" ) )
					break;
				return;

			default:
				return;

		}

		if( m() > 1 )
			m_k = m_j;

	}

	/**
	 * step5() removes a final -e if m() > 1, and changes -ll to -l if m() > 1.
	 */
	private void step5()
	{
		m_j = m_k;
		if( m_b[ m_k ] == 'e' )
		{
			auto a = m();
			if( a > 1 || (a == 1 && !cvc( m_k - 1 ) ) )
				m_k--;
		}
		if( m_b[ m_k ] == 'l' && doublec( m_k ) && m() > 1 )
			m_k--;
		
	}

	/**
	 * In stem(p,i,j), p is a char pointer, and the string to be stemmed
     * is from p[i] to p[j] inclusive. Typically i is zero and j is the
     * offset to the last character of a string, (p[j+1] == '\0'). The
     * stemmer adjusts the characters p[i] ... p[j] and returns the new
     * end-point of the string, k. Stemming never increases word length, so
     * i <= k <= j. To turn the stemmer into a module, declare 'stem' as
     * extern, and delete the remainder of this file.
	 */
	public const(char)[] stem(const char[] p)
	{

		m_b = p;
		m_k = cast(int) p.length-1;
		m_k0 = 0;
		
		/**
		 * --DEPARTURE--
		 *
		 * With this line, strings of length 1 or 2 don't go through the
		 * stemming process, although no mention is made of this in the
		 * published algorithm. Remove the line to match the published
		 * algorithm.
		 *
		 */
		if( m_k <= m_k0 + 1 )
			return m_b;
			
		step1ab();
		step1c();
		step2();
		step3();
		step4();
		step5();
		return m_b[ m_k0 .. m_k + 1 ];
		
	}

}


